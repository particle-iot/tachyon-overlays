/*
 * camx-v4l2-bridge - feed CamX HAL3 frames into a v4l2loopback node.
 *
 * CamX exposes HAL3 only, so ordinary V4L2 consumers (ffmpeg, OpenCV,
 * GStreamer's v4l2src, PipeWire) cannot open the camera. This daemon pulls
 * frames from the HAL and writes them to a loopback output node, which those
 * consumers then see as a normal capture device.
 *
 * Costs, which is why it is opt-in and a separate package:
 *   - one resident process, roughly one core of an 8-core board
 *   - one extra copy per frame (de-stride + chroma swap)
 *   - the HAL3 camera is held open, so native clients cannot use it while
 *     this runs. CamX does not support opening a camera from two processes.
 *
 * Unlike camx-capture, this is long-running: it handles SIGTERM/SIGINT and
 * every exit goes through one teardown path, so systemd stop/restart leaves
 * the HAL in a state where the next open() succeeds.
 *
 * Build:
 *   aarch64-linux-gnu-gcc -O2 -o camx-v4l2-bridge camx-v4l2-bridge.c -ldl -lpthread
 */
#include "camx-hal.h"
#include <signal.h>
#include <sys/stat.h>
#include <getopt.h>

/* Set from the signal handler; only ever written with a plain store. */
static volatile sig_atomic_t g_stop;

static void on_signal(int sig)
{
	(void)sig;
	g_stop = 1;
}

/*
 * Configure a v4l2loopback node as an NV12 sink and return its fd.
 *
 * The device is opened by path, but the caller is expected to hand us a udev
 * symlink rather than /dev/videoN: loopback numbering is dynamic, and pinning
 * a number collides with whatever else claims video nodes on the board.
 *
 * The driver accepts a plain write() of one packed frame, so there is no
 * buffer negotiation on this side.
 */
static int v4l2_open_sink(const char *path, int w, int h, size_t frame_sz)
{
	struct stat st;
	if (stat(path, &st) < 0) { perror(path); return -1; }
	if (!S_ISCHR(st.st_mode)) {
		fprintf(stderr, "%s is not a character device\n", path);
		return -1;
	}

	int fd = open(path, O_RDWR);
	if (fd < 0) { perror(path); return -1; }

	struct v4l2_capability cap;
	memset(&cap, 0, sizeof(cap));
	if (ioctl(fd, VIDIOC_QUERYCAP, &cap) == 0)
		printf("sink: %s (%s)\n", cap.card, cap.driver);

	struct v4l2_format f;
	memset(&f, 0, sizeof(f));
	f.type = V4L2_BUF_TYPE_VIDEO_OUTPUT;
	f.fmt.pix.width        = w;
	f.fmt.pix.height       = h;
	f.fmt.pix.pixelformat  = V4L2_PIX_FMT_NV12;
	f.fmt.pix.field        = V4L2_FIELD_NONE;
	f.fmt.pix.bytesperline = w;
	f.fmt.pix.sizeimage    = frame_sz;
	f.fmt.pix.colorspace   = V4L2_COLORSPACE_SRGB;
	if (ioctl(fd, VIDIOC_S_FMT, &f) < 0) {
		perror("VIDIOC_S_FMT");
		close(fd);
		return -1;
	}
	/*
	 * S_FMT returning 0 does not mean the driver took what we asked for -
	 * V4L2 lets it substitute a format it does support. Read back what it
	 * actually stored. (v4l2loopback has no NV21, and silently answering
	 * with BGR4 is exactly how this went wrong once.)
	 */
	if (f.fmt.pix.pixelformat != V4L2_PIX_FMT_NV12 ||
	    f.fmt.pix.width != (uint32_t)w || f.fmt.pix.height != (uint32_t)h) {
		fprintf(stderr, "sink rejected NV12 %dx%d, gave %.4s %ux%u\n",
			w, h, (char *)&f.fmt.pix.pixelformat,
			f.fmt.pix.width, f.fmt.pix.height);
		close(fd);
		return -1;
	}
	printf("sink format: %dx%d NV12, sizeimage=%u\n", w, h, f.fmt.pix.sizeimage);
	return fd;
}

static void usage(const char *argv0)
{
	fprintf(stderr,
"usage: %s --v4l2-output PATH [--camera N] [--size WxH]\n"
"\n"
"  --v4l2-output PATH   v4l2loopback node to write to, e.g. /dev/tachyon-camera\n"
"  --camera N           HAL camera id (CSI1 is 0, CSI2 is 1). default 0\n"
"  --size WxH           capture size, must be one the HAL advertises. default 1280x960\n"
"\n"
"Holds the HAL3 camera open for as long as it runs; native clients such as\n"
"camx-capture cannot use that camera meanwhile. Stops cleanly on SIGTERM.\n",
		argv0);
}

int main(int argc, char **argv)
{
	setvbuf(stdout, NULL, _IONBF, 0);
	setvbuf(stderr, NULL, _IONBF, 0);

	const char *sink_path = NULL;
	int cam_index = 0, W = 1280, H = 960;

	static struct option opts[] = {
		{ "v4l2-output", required_argument, 0, 'o' },
		{ "camera",      required_argument, 0, 'c' },
		{ "size",        required_argument, 0, 's' },
		{ "help",        no_argument,       0, 'h' },
		{ 0, 0, 0, 0 }
	};
	int c;
	while ((c = getopt_long(argc, argv, "o:c:s:h", opts, NULL)) != -1) {
		switch (c) {
		case 'o': sink_path = optarg; break;
		case 'c':
			cam_index = atoi(optarg);
			if (cam_index < 0) { fprintf(stderr, "bad --camera\n"); return 2; }
			break;
		case 's':
			if (sscanf(optarg, "%dx%d", &W, &H) != 2 || W <= 0 || H <= 0) {
				fprintf(stderr, "bad --size, want WxH\n"); return 2;
			}
			break;
		case 'h': usage(argv[0]); return 0;
		default:  usage(argv[0]); return 2;
		}
	}
	if (!sink_path) { usage(argv[0]); return 2; }

	/*
	 * Install handlers before anything is acquired. SA_RESTART is left off
	 * so a signal breaks the blocking wait in the frame loop instead of
	 * being swallowed until the next result arrives.
	 */
	struct sigaction sa;
	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = on_signal;
	sigaction(SIGTERM, &sa, NULL);
	sigaction(SIGINT,  &sa, NULL);
	signal(SIGPIPE, SIG_IGN);   /* consumer closing the node must not kill us */

	/*
	 * Everything acquired below is released through the single `out:` path,
	 * so any failure still tears the HAL down properly - a half-closed CamX
	 * session makes the *next* open() fail, which under systemd turns one
	 * bad start into a restart loop.
	 */
	int rc_exit = 1;
	void *lib = NULL;
	struct hw_device *dev = NULL;
	struct camera3_device *cam = NULL;
	int v4l2_fd = -1;
	uint8_t *stage = NULL;
	void *settings = NULL;
	int heap_fd_open = 0;
	size_t slot_sz = 0;

	lib = dlopen(HAL_PATH, RTLD_NOW);
	if (!lib) { fprintf(stderr, "dlopen: %s\n", dlerror()); goto out; }
	struct camera_module *mod = dlsym(lib, "HMI");
	if (!mod || mod->common.tag != HARDWARE_MODULE_TAG) {
		fprintf(stderr, "bad HMI\n"); goto out;
	}
	int ncam = mod->get_number_of_cameras();
	if (ncam <= 0) { fprintf(stderr, "no cameras\n"); goto out; }
	if (cam_index >= ncam) {
		fprintf(stderr, "--camera %d but only %d present"
			" (is the matching overlay enabled?)\n", cam_index, ncam);
		goto out;
	}
	printf("cameras: %d, using %d\n", ncam, cam_index);

	char cam_id[16];
	snprintf(cam_id, sizeof(cam_id), "%d", cam_index);

	struct hw_module_methods *mm = mod->common.methods;
	int rc = mm->open(&mod->common, cam_id, &dev);
	if (rc || !dev) { fprintf(stderr, "open failed rc=%d\n", rc); dev = NULL; goto out; }
	cam = (struct camera3_device *)dev;

	static struct camera3_callback_ops cbs = { on_result, on_notify, NULL, NULL };
	rc = cam->ops->initialize(dev, &cbs);
	if (rc) { fprintf(stderr, "initialize rc=%d\n", rc); goto out; }

	struct camera3_stream st;
	memset(&st, 0, sizeof(st));
	st.stream_type = 0;                  /* OUTPUT */
	st.width = W; st.height = H;
	st.format = 0x23;                    /* HAL_PIXEL_FORMAT_YCbCr_420_888 */
	st.usage = 0x00000003;
	st.data_space = 0;
	st.rotation = 0;
	struct camera3_stream *streams[1] = { &st };
	struct camera3_stream_configuration cfg;
	memset(&cfg, 0, sizeof(cfg));
	cfg.num_streams = 1;
	cfg.streams = streams;
	cfg.operation_mode = 0;
	rc = cam->ops->configure_streams(dev, &cfg);
	if (rc) {
		fprintf(stderr, "configure_streams rc=%d - is %dx%d advertised?\n", rc, W, H);
		goto out;
	}

	const size_t ystride = ALIGN_UP((size_t)W, 64);
	const size_t yscan   = ALIGN_UP((size_t)H, 64);
	slot_sz = ystride * yscan * 3 / 2;
	const size_t packed_sz = (size_t)W * H * 3 / 2;

	v4l2_fd = v4l2_open_sink(sink_path, W, H, packed_sz);
	if (v4l2_fd < 0) goto out;

	stage = malloc(packed_sz);
	if (!stage) { perror("malloc"); goto out; }

	for (int k = 0; k < NBUF; k++) {
		g_slots[k].fd = dma_alloc(slot_sz);
		if (g_slots[k].fd < 0) goto out;
		heap_fd_open = k + 1;
		g_slots[k].size = slot_sz;
		g_slots[k].map = mmap(NULL, slot_sz, PROT_READ, MAP_SHARED, g_slots[k].fd, 0);
		if (g_slots[k].map == MAP_FAILED) { perror("mmap"); g_slots[k].map = NULL; goto out; }

		struct slot *s = &g_slots[k];
		/* Must match what the HAL expects field for field - a wrong
		 * numFds/numInts or a missing buffer_type comes back as
		 * NOTIFY ERROR code 4 (BUFFER) on every frame. */
		s->ph.version = (int)sizeof(struct native_handle);
		s->ph.numFds  = 2;
		s->ph.numInts = (int)((sizeof(struct priv_handle) - sizeof(struct native_handle))
				      / sizeof(int)) - 2;
		s->ph.fd = s->fd; s->ph.fd_metadata = -1;
		s->ph.magic = PRIV_MAGIC;
		s->ph.width = (int)ystride; s->ph.height = (int)yscan;
		s->ph.unaligned_width = W; s->ph.unaligned_height = H;
		s->ph.format = 0x23; s->ph.buffer_type = 1;
		s->ph.layer_count = 1;
		s->ph.usage = st.usage;
		s->ph.size = (unsigned)slot_sz;
		s->ph.id = (uint64_t)k;
		s->handle = &s->ph;
		s->sb.stream = &st;
		s->sb.buffer = &s->handle;
		s->sb.status = 0;
		s->sb.acquire_fence = -1;
		s->sb.release_fence = -1;
	}

	const void *ro = cam->ops->construct_default_request_settings(dev, 1 /* PREVIEW */);
	if (!ro) { fprintf(stderr, "no default settings\n"); goto out; }
	const struct cam_meta *rom = ro;
	settings = malloc(rom->size);
	if (!settings) { perror("malloc settings"); goto out; }
	memcpy(settings, ro, rom->size);

	uint32_t next_frame = 0;
	for (int k = 0; k < NBUF; k++) {
		struct camera3_capture_request req;
		memset(&req, 0, sizeof(req));
		req.frame_number = next_frame++;
		req.settings = settings;
		req.num_output_buffers = 1;
		req.output_buffers = &g_slots[k].sb;
		rc = cam->ops->process_capture_request(dev, &req);
		if (rc) { fprintf(stderr, "initial request rc=%d\n", rc); goto out; }
	}

	printf("streaming %dx%d NV12 -> %s\n", W, H, sink_path);

	struct timespec t0;
	clock_gettime(CLOCK_MONOTONIC, &t0);
	unsigned long pushed = 0, dropped = 0;
	int consecutive_timeouts = 0;

	while (!g_stop) {
		struct timespec ts;
		clock_gettime(CLOCK_REALTIME, &ts);
		ts.tv_sec += 5;

		int k = -1, kstat = 0, kfence = -1;
		pthread_mutex_lock(&g_lock);
		while (g_nready == 0 && !g_stop) {
			if (pthread_cond_timedwait(&g_cond, &g_lock, &ts) != 0) break;
		}
		for (int i = 0; i < NBUF; i++) {
			if (g_ready[i]) {
				k = i;
				kstat = g_ready_status[i]; kfence = g_ready_fence[i];
				g_ready[i] = 0; g_nready--; break;
			}
		}
		pthread_mutex_unlock(&g_lock);

		if (g_stop) break;
		if (k < 0) {
			/*
			 * Bounded, not infinite: if the pipeline stops delivering
			 * we exit non-zero and let systemd's rate limit stop the
			 * restarts, rather than spinning here forever.
			 */
			if (++consecutive_timeouts >= 3) {
				fprintf(stderr, "no frames for %ds, giving up\n", 5 * 3);
				goto out;
			}
			continue;
		}
		consecutive_timeouts = 0;

		consume_release_fence(kfence);

		if (kstat == 0) {
			struct dma_buf_sync sy = { .flags = DMA_BUF_SYNC_START | DMA_BUF_SYNC_READ };
			ioctl(g_slots[k].fd, DMA_BUF_IOCTL_SYNC, &sy);
			const uint8_t *src = g_slots[k].map;
			for (int r = 0; r < H; r++)
				memcpy(stage + (size_t)r * W, src + (size_t)r * ystride, W);
			/*
			 * The IPE emits NV21 (V first) but v4l2loopback only
			 * advertises NV12, so swap each chroma byte pair while
			 * de-striding rather than paying for a second pass.
			 */
			uint8_t *cdst = stage + (size_t)W * H;
			for (int r = 0; r < (H + 1) / 2; r++) {
				const uint8_t *s = src + (size_t)(yscan + r) * ystride;
				uint8_t *d = cdst + (size_t)r * W;
				for (int cc = 0; cc + 1 < W; cc += 2) {
					d[cc]     = s[cc + 1];   /* U */
					d[cc + 1] = s[cc];       /* V */
				}
			}
			sy.flags = DMA_BUF_SYNC_END | DMA_BUF_SYNC_READ;
			ioctl(g_slots[k].fd, DMA_BUF_IOCTL_SYNC, &sy);

			size_t off = 0;
			while (off < packed_sz) {
				ssize_t n = write(v4l2_fd, stage + off, packed_sz - off);
				if (n < 0 && errno == EINTR) continue;   /* signal, retry */
				if (n <= 0) break;
				off += (size_t)n;
			}
			if (off == packed_sz) pushed++; else dropped++;
		} else {
			dropped++;
		}

		if (((pushed + dropped) % 300) == 0) {
			struct timespec t1;
			clock_gettime(CLOCK_MONOTONIC, &t1);
			double el = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
			printf("%lu pushed, %lu dropped, %.1f fps\n",
			       pushed, dropped, el > 0 ? pushed / el : 0.0);
		}

		/* Hand the buffer straight back so the pipeline never runs dry. */
		struct camera3_capture_request req;
		memset(&req, 0, sizeof(req));
		req.frame_number = next_frame++;
		req.settings = settings;
		req.num_output_buffers = 1;
		req.output_buffers = &g_slots[k].sb;
		rc = cam->ops->process_capture_request(dev, &req);
		if (rc) { fprintf(stderr, "resubmit rc=%d\n", rc); goto out; }
	}

	printf("stopping: %lu pushed, %lu dropped\n", pushed, dropped);
	rc_exit = 0;

out:
	/*
	 * One teardown path for every exit. Closing the HAL device first stops
	 * the pipeline before its buffers go away; doing it the other way round
	 * leaves the kernel signalling sync objects that no longer exist.
	 */
	if (dev && dev->close)
		dev->close(dev);
	for (int k = 0; k < heap_fd_open; k++) {
		if (g_slots[k].map)
			munmap(g_slots[k].map, g_slots[k].size);
		if (g_slots[k].fd >= 0)
			close(g_slots[k].fd);
	}
	if (v4l2_fd >= 0) close(v4l2_fd);
	free(stage);
	free(settings);
	if (lib) dlclose(lib);
	return rc_exit;
}
