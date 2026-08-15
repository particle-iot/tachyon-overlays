/*
 * camx-capture - single-frame and raw-recording CamX HAL3 client for QCM6490.
 *
 * Validates the hardware ISP path (CSIPHY -> CSID -> IFE -> IPE) without the
 * vendor test tool, which drags in Android binder and cannot run here. This is
 * a smoke test: every error path exits immediately with a distinct status.
 *
 * Live streaming into a v4l2loopback node is a separate program,
 * camx-v4l2-bridge - a long-running daemon has different requirements
 * (signal handling, one teardown path) than a test that should fail fast.
 *
 * Build:
 *   aarch64-linux-gnu-gcc -O2 -o camx-capture camx-capture.c -ldl -lpthread
 */
#include "camx-hal.h"


int main(int argc, char **argv)
{
	setvbuf(stdout, NULL, _IONBF, 0);
	setvbuf(stderr, NULL, _IONBF, 0);
	int W = argc > 1 ? atoi(argv[1]) : 1280;
	int H = argc > 2 ? atoi(argv[2]) : 720;
	/* NV21, not NV12 - the IPE emits V before U. */
	const char *out = argc > 3 ? argv[3] : "/tmp/frame.nv21";
	/* HAL_PIXEL_FORMAT_YCbCr_420_888 */
	const int fmt = 0x23;

	void *lib = dlopen(HAL_PATH, RTLD_NOW);
	if (!lib) { fprintf(stderr, "dlopen: %s\n", dlerror()); return 1; }
	struct camera_module *mod = dlsym(lib, "HMI");
	if (!mod || mod->common.tag != HARDWARE_MODULE_TAG) {
		fprintf(stderr, "bad HMI\n"); return 1;
	}
	int n = mod->get_number_of_cameras();
	printf("cameras: %d\n", n);
	if (n <= 0) return 2;

	/*
	 * Which camera to open. An environment variable rather than an argument
	 * so the positional ones keep their meaning; with both connectors
	 * enabled, CSI1 is id 0 and CSI2 is id 1.
	 */
	const char *cam_id = getenv("CAMX_CAM_ID");
	if (!cam_id || !*cam_id)
		cam_id = "0";
	if (atoi(cam_id) >= n) {
		fprintf(stderr, "CAMX_CAM_ID=%s but only %d camera(s) present\n", cam_id, n);
		return 2;
	}

	/*
	 * "static" as the first argument dumps the camera characteristics and
	 * exits. configure_streams rejects any size the HAL did not advertise
	 * there with -EINVAL, so this is what decides which resolutions work.
	 */
	if (argc > 1 && !strcmp(argv[1], "static")) {
		struct camera_info info;
		memset(&info, 0, sizeof(info));
		if (mod->get_camera_info(atoi(cam_id), &info) || !info.static_camera_characteristics) {
			fprintf(stderr, "get_camera_info failed\n"); return 2;
		}
		meta_dump_n(info.static_camera_characteristics, 4096);
		return 0;
	}

	struct hw_module_methods *mm = mod->common.methods;
	struct hw_device *dev = NULL;
	int rc = mm->open(&mod->common, cam_id, &dev);
	if (rc || !dev) { fprintf(stderr, "open failed rc=%d\n", rc); return 3; }
	struct camera3_device *cam = (struct camera3_device *)dev;
	printf("opened camera %s, device version 0x%x\n", cam_id, dev->version);

	static struct camera3_callback_ops cbs = { on_result, on_notify, NULL, NULL };
	rc = cam->ops->initialize(dev, &cbs);
	if (rc) { fprintf(stderr, "initialize rc=%d\n", rc); return 4; }

	struct camera3_stream st;
	memset(&st, 0, sizeof(st));
	st.stream_type = 0;              /* OUTPUT */
	st.width = W; st.height = H;
	st.format = fmt;
	st.usage = 0x00000003;           /* SW_READ_OFTEN | SW_WRITE_OFTEN */
	st.data_space = 0;
	st.rotation = 0;

	struct camera3_stream *streams[1] = { &st };
	struct camera3_stream_configuration cfg;
	memset(&cfg, 0, sizeof(cfg));
	cfg.num_streams = 1;
	cfg.streams = streams;
	cfg.operation_mode = 0;          /* NORMAL */

	rc = cam->ops->configure_streams(dev, &cfg);
	if (rc) { fprintf(stderr, "configure_streams rc=%d\n", rc); return 5; }
	printf("configured %dx%d fmt=0x%x max_buffers=%u usage=0x%x\n",
	       W, H, fmt, st.max_buffers, st.usage);

	int ystride = ALIGN_UP(W, 128);
	int yscan   = ALIGN_UP(H, 64);
	int cscan   = ALIGN_UP((H + 1) / 2, 64);
	size_t sz   = (size_t)ystride * (yscan + cscan);
	/* what a consumer expects: no stride padding, chroma right after luma */
	size_t packed_sz = (size_t)W * H + (size_t)W * ((H + 1) / 2);
	printf("buffer: stride=%d yscan=%d cscan=%d size=%zu (packed would be %zu)\n",
	       ystride, yscan, cscan, sz, (size_t)W * H * 3 / 2);
	for (int k = 0; k < NBUF; k++) {
		struct slot *s = &g_slots[k];
		s->size = sz;
		s->fd = dma_alloc(sz);
		if (s->fd < 0) return 6;

		s->ph.version = (int)sizeof(struct native_handle);
		s->ph.numFds  = 2;
		s->ph.numInts = (int)((sizeof(struct priv_handle) - sizeof(struct native_handle))
				      / sizeof(int)) - 2;
		s->ph.fd = s->fd; s->ph.fd_metadata = -1;
		s->ph.magic = PRIV_MAGIC;
		s->ph.width = ystride; s->ph.height = yscan;
		s->ph.unaligned_width = W; s->ph.unaligned_height = H;
		s->ph.format = fmt; s->ph.buffer_type = 1;
		s->ph.layer_count = 1;
		s->ph.usage = st.usage;
		s->ph.size = (unsigned int)sz;
		s->ph.id = (uint64_t)k;

		s->handle = &s->ph;
		s->sb.stream = &st;
		s->sb.buffer = &s->handle;
		s->sb.status = 0;
		s->sb.acquire_fence = -1;
		s->sb.release_fence = -1;
	}

	const void *ro_settings = cam->ops->construct_default_request_settings(dev, 1 /* PREVIEW */);
	if (!ro_settings) { fprintf(stderr, "no default settings\n"); return 7; }

	/* Work on a private copy so request tags can be overridden from argv. */
	const struct cam_meta *rom = ro_settings;
	void *settings = malloc(rom->size);
	if (!settings) { perror("malloc settings"); return 7; }
	memcpy(settings, ro_settings, rom->size);
	meta_dump_n(settings, 6);
	for (int a = 4; a < argc; a++) {
		unsigned int tag; double v;
		if (sscanf(argv[a], "%x=%lf", &tag, &v) == 2)
			meta_set(settings, tag, v);
		else
			fprintf(stderr, "bad override '%s', want <hextag>=<value>\n", argv[a]);
	}

	uint32_t next_frame = 0;
	for (int k = 0; k < NBUF; k++) {
		struct camera3_capture_request req;
		memset(&req, 0, sizeof(req));
		req.frame_number = next_frame++;
		req.settings = settings;
		req.num_output_buffers = 1;
		req.output_buffers = &g_slots[k].sb;
		rc = cam->ops->process_capture_request(dev, &req);
		if (rc) { fprintf(stderr, "process_capture_request[%d] rc=%d\n", k, rc); return 8; }
	}
	printf("%d requests queued, draining to frame %d...\n", NBUF, TARGET_FRAME);

	int raw_fd  = -1;
	long raw_want = 0;              /* frames to record, 0 = single-shot */
	uint8_t *stage = NULL;

	/*
	 * Two sinks:
	 *   file + CAMX_FRAMES - record N frames of raw NV21 back to back
	 *   file               - single shot
	 *
	 * Recording raw and encoding afterwards avoids the frame drops that come
	 * from asking an encoder to keep up in real time, which matters at 4K.
	 *
	 * Feeding a v4l2loopback node lives in camx-v4l2-bridge, which is a
	 * daemon: it needs signal handling and a single teardown path, whereas
	 * this tool is a smoke test and should fail fast.
	 */
	{
		const char *nf = getenv("CAMX_FRAMES");
		if (nf && *nf) {
			raw_want = strtol(nf, NULL, 10);
			if (raw_want <= 0) { fprintf(stderr, "CAMX_FRAMES must be > 0\n"); return 12; }
			raw_fd = open(out, O_WRONLY | O_CREAT | O_TRUNC, 0644);
			if (raw_fd < 0) { perror(out); return 12; }
		}
	}

	if (raw_fd >= 0) {
		stage = malloc(packed_sz);
		if (!stage) { perror("malloc stage"); return 12; }
		printf("recording %ld frames of %dx%d NV21 -> %s\n", raw_want, W, H, out);
		for (int k = 0; k < NBUF; k++) {
			g_slots[k].map = mmap(NULL, sz, PROT_READ, MAP_SHARED, g_slots[k].fd, 0);
			if (g_slots[k].map == MAP_FAILED) { perror("mmap slot"); return 12; }
		}
	}

	int final_slot = -1;
	unsigned long pushed = 0, dropped = 0;
	struct timespec t0;
	clock_gettime(CLOCK_MONOTONIC, &t0);

	while (final_slot < 0) {
		struct timespec ts;
		clock_gettime(CLOCK_REALTIME, &ts);
		ts.tv_sec += 5;

		int k = -1, kstat = 0, kfence = -1;
		uint32_t kf = 0;
		pthread_mutex_lock(&g_lock);
		while (g_nready == 0) {
			if (pthread_cond_timedwait(&g_cond, &g_lock, &ts) != 0) break;
		}
		for (int i = 0; i < NBUF; i++) {
			if (g_ready[i]) {
				k = i; kf = g_ready_frame[i];
				kstat = g_ready_status[i]; kfence = g_ready_fence[i];
				g_ready[i] = 0; g_nready--; break;
			}
		}
		pthread_mutex_unlock(&g_lock);

		if (k < 0) { fprintf(stderr, "timeout at frame %u\n", next_frame); return 9; }

		/* Buffer contents are only valid once this has signalled. */
		consume_release_fence(kfence);

		if (raw_fd >= 0) {
			if (kstat == 0) {
				/* de-stride into a packed frame, then hand it to the sink */
				struct dma_buf_sync sy = { .flags = DMA_BUF_SYNC_START | DMA_BUF_SYNC_READ };
				ioctl(g_slots[k].fd, DMA_BUF_IOCTL_SYNC, &sy);
				const uint8_t *src = g_slots[k].map;
				for (int r = 0; r < H; r++)
					memcpy(stage + (size_t)r * W, src + (size_t)r * ystride, W);
				/* Recording keeps the IPE's native NV21 (V first). */
				uint8_t *cdst = stage + (size_t)W * H;
				for (int r = 0; r < (H + 1) / 2; r++)
					memcpy(cdst + (size_t)r * W,
					       src + (size_t)(yscan + r) * ystride, W);
				sy.flags = DMA_BUF_SYNC_END | DMA_BUF_SYNC_READ;
				ioctl(g_slots[k].fd, DMA_BUF_IOCTL_SYNC, &sy);

				int sink = raw_fd;
				/* A short write on a regular file is not an error - loop. */
				size_t off = 0;
				ssize_t n = 0;
				while (off < packed_sz) {
					n = write(sink, stage + off, packed_sz - off);
					if (n <= 0) break;
					off += (size_t)n;
				}
				if (off == packed_sz) pushed++;
				else dropped++;
				if ((long)pushed >= raw_want) break;
			} else {
				dropped++;
			}
			if (((pushed + dropped) % 30) == 0) {
				struct timespec t1;
				clock_gettime(CLOCK_MONOTONIC, &t1);
				double el = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
				printf("\r  %lu frames pushed, %lu dropped, %.1f fps  ",
				       pushed, dropped, el > 0 ? pushed / el : 0.0);
				fflush(stdout);
			}
		} else {
			printf("  result frame %u (slot %d) status=%d release_fence=%d\n",
			       kf, k, kstat, kfence);
			/* Errored buffers come back with status=1 and untouched memory,
			 * and they arrive in bursts, so wait for a good one. */
			if (kstat == 0 && kf >= TARGET_FRAME) { final_slot = k; break; }
		}

		/* hand the buffer straight back so the pipeline never runs dry */
		struct camera3_capture_request req;
		memset(&req, 0, sizeof(req));
		req.frame_number = next_frame++;
		req.settings = settings;
		req.num_output_buffers = 1;
		req.output_buffers = &g_slots[k].sb;
		rc = cam->ops->process_capture_request(dev, &req);
		if (rc) { fprintf(stderr, "resubmit rc=%d at frame %u\n", rc, req.frame_number); return 8; }
	}

	if (raw_fd >= 0) {
		struct timespec t1;
		clock_gettime(CLOCK_MONOTONIC, &t1);
		double el = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
		fsync(raw_fd);
		close(raw_fd);
		printf("\nrecorded %lu frames (%lu dropped) in %.1fs = %.1f fps -> %s\n",
		       pushed, dropped, el, el > 0 ? pushed / el : 0.0, out);
		if (dev->close) dev->close(dev);
		for (int k = 0; k < NBUF; k++) close(g_slots[k].fd);
		return pushed ? 0 : 12;
	}

	int ffd = g_slots[final_slot].fd;
	void *p = mmap(NULL, sz, PROT_READ, MAP_SHARED, ffd, 0);
	if (p == MAP_FAILED) { perror("mmap"); return 10; }
	struct dma_buf_sync sync = { .flags = DMA_BUF_SYNC_START | DMA_BUF_SYNC_READ };
	if (ioctl(ffd, DMA_BUF_IOCTL_SYNC, &sync) < 0) perror("DMA_BUF_SYNC_START");
	FILE *f = fopen(out, "wb");
	if (!f) { perror("fopen"); return 11; }
	const uint8_t *src = p;
	for (int r = 0; r < H; r++)
		fwrite(src + (size_t)r * ystride, 1, W, f);
	for (int r = 0; r < (H + 1) / 2; r++)
		fwrite(src + (size_t)(yscan + r) * ystride, 1, W, f);
	fclose(f);

	/* crude sanity: a real frame is not uniformly zero */
	const uint8_t *b = p;
	size_t nz = 0, ymax = 0, ysum = 0;
	for (int r = 0; r < H; r++)
		for (int c = 0; c < W; c++) {
			uint8_t v = b[(size_t)r * ystride + c];
			if (v) nz++;
			if (v > ymax) ymax = v;
			ysum += v;
		}
	printf("frame written to %s (packed %zu bytes), non-zero Y: %zu/%d, max=%zu avg=%zu\n",
	       out, (size_t)W * H * 3 / 2, nz, W * H, ymax, ysum / ((size_t)W * H));

	sync.flags = DMA_BUF_SYNC_END | DMA_BUF_SYNC_READ;
	if (ioctl(ffd, DMA_BUF_IOCTL_SYNC, &sync) < 0) perror("DMA_BUF_SYNC_END");
	munmap(p, sz);

	/* Without an explicit close the HAL is torn down by the process exit while
	 * the pipeline is still streaming, which leaves the kernel signalling sync
	 * objects that have already gone away. */
	if (dev->close)
		dev->close(dev);
	for (int k = 0; k < NBUF; k++)
		close(g_slots[k].fd);
	return nz ? 0 : 12;
}
