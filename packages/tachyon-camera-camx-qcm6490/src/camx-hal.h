/*
 * camx-hal.h - CamX HAL3 ABI and shared helpers for the Tachyon smoke-test
 * clients (camx-enum, camx-capture) and the V4L2 bridge (camx-v4l2-bridge).
 *
 * The vendor headers are C++ and drag in Android build glue, so the structures
 * below are POD equivalents checked against the originals with static asserts:
 * a layout change fails the build rather than corrupting memory at runtime.
 *
 * Header-only on purpose. Each tool is a single translation unit, so the
 * static definitions cost nothing and the alternative - a shared .c plus a
 * build system to link it - buys nothing at this size.
 */
#ifndef CAMX_HAL_H
#define CAMX_HAL_H

#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <linux/ioctl.h>
#include <poll.h>
#include <time.h>
#include <sys/mman.h>
#include <unistd.h>
#include <pthread.h>
#include <linux/videodev2.h>

#define HAL_PATH            "/usr/lib/hw/camera.qcom.so"
#define HARDWARE_MODULE_TAG 0x48574d54u   /* 'HWMT' */
#define DMA_HEAP            "/dev/dma_heap/system"

/* ---- dma-heap uapi (avoid depending on kernel headers) ---- */
struct dma_heap_allocation_data {
	uint64_t len;
	uint32_t fd;
	uint32_t fd_flags;
	uint64_t heap_flags;
};
_Static_assert(sizeof(struct dma_heap_allocation_data) == 24, "dma_heap uapi mismatch");
#define DMA_HEAP_IOCTL_ALLOC _IOWR('H', 0, struct dma_heap_allocation_data)

/*
 * The system heap is cached, so a CPU mapping is not coherent with what the
 * ISP wrote until the buffer is synced. Skipping this reads stale lines and
 * a perfectly good frame looks uniformly black.
 */
struct dma_buf_sync { uint64_t flags; };
#define DMA_BUF_SYNC_READ   (1 << 0)
#define DMA_BUF_SYNC_START  (0 << 2)
#define DMA_BUF_SYNC_END    (1 << 2)
#define DMA_BUF_IOCTL_SYNC  _IOW('b', 0, struct dma_buf_sync)

/* ---- Android hw_module_t / camera_module_t (verified against HMI) ---- */
struct hw_module {
	uint32_t tag;
	uint16_t module_api_version, hal_api_version;
	const char *id, *name, *author;
	void *methods, *dso;
	uint64_t reserved[25];
};
_Static_assert(sizeof(struct hw_module) == 248, "hw_module_t layout changed");

struct hw_device;
struct hw_module_methods {
	int (*open)(const struct hw_module *m, const char *id, struct hw_device **d);
};

struct camera_info {
	int facing, orientation;
	uint32_t device_version;
	const void *static_camera_characteristics;
	int resource_cost;
	char **conflicting_devices;
	size_t conflicting_devices_length;
};

struct camera_module {
	struct hw_module common;
	int (*get_number_of_cameras)(void);
	int (*get_camera_info)(int id, struct camera_info *info);
	int (*set_callbacks)(const void *cb);
	void (*get_vendor_tag_ops)(void *ops);
	int (*open_legacy)(const struct hw_module *m, const char *id, uint32_t v,
			   struct hw_device **d);
	int (*set_torch_mode)(const char *id, int on);
	int (*init)(void);
};
_Static_assert(offsetof(struct camera_module, get_number_of_cameras) == 248, "bad offset");

/* ---- camera3 ---- */
struct hw_device {
	uint32_t tag;
	uint32_t version;
	struct hw_module *module;
	uint64_t reserved[12];
	int (*close)(struct hw_device *d);
};

struct camera3_stream {
	int stream_type;
	uint32_t width, height;
	int format;
	uint32_t usage, max_buffers;
	void *priv;
	int data_space;
	int rotation;
	const char *physical_camera_id;
	void *reserved[6];
};

struct camera3_stream_configuration {
	uint32_t num_streams;
	struct camera3_stream **streams;
	uint32_t operation_mode;
	const void *session_parameters;
};

struct camera3_stream_buffer {
	struct camera3_stream *stream;
	void **buffer;            /* buffer_handle_t*  = native_handle** */
	int status;
	int acquire_fence, release_fence;
};

struct camera3_capture_request {
	uint32_t frame_number;
	const void *settings;
	struct camera3_stream_buffer *input_buffer;
	uint32_t num_output_buffers;
	const struct camera3_stream_buffer *output_buffers;
	uint32_t num_physcam_settings;
	const char **physcam_id;
	const void **physcam_settings;
};

struct camera3_capture_result {
	uint32_t frame_number;
	const void *result;
	uint32_t num_output_buffers;
	const struct camera3_stream_buffer *output_buffers;
	const struct camera3_stream_buffer *input_buffer;
	uint32_t partial_result;
	uint32_t num_physcam_metadata;
	const char **physcam_ids;
	const void **physcam_metadata;
};

struct camera3_callback_ops {
	void (*process_capture_result)(const struct camera3_callback_ops *cb,
				       const struct camera3_capture_result *r);
	void (*notify)(const struct camera3_callback_ops *cb, const void *msg);
	int  (*request_stream_buffers)(const struct camera3_callback_ops *cb,
				       const void *in, void *out);
	void (*return_stream_buffers)(const struct camera3_callback_ops *cb,
				      uint32_t n, const struct camera3_stream_buffer *b);
};

struct camera3_device_ops {
	int  (*initialize)(const struct hw_device *d, const struct camera3_callback_ops *cb);
	int  (*configure_streams)(const struct hw_device *d,
				  struct camera3_stream_configuration *cfg);
	int  (*construct_default_request_settings_unused)(const struct hw_device *d, int type);
	const void *(*construct_default_request_settings)(const struct hw_device *d, int type);
	int  (*process_capture_request)(const struct hw_device *d,
					struct camera3_capture_request *req);
};

struct camera3_device {
	struct hw_device common;
	struct camera3_device_ops *ops;
	void *priv;
};

/* ---- gralloc private_handle_t, POD equivalent ---- */
struct native_handle {
	int version, numFds, numInts;
};

struct priv_handle {
	int version, numFds, numInts;          /* native_handle_t */
	int fd, fd_metadata;
	int magic, flags, width, height;
	int unaligned_width, unaligned_height;
	int format, buffer_type;
	unsigned int layer_count;
	uint64_t id, usage;
	unsigned int size, offset, offset_metadata;
	uint64_t base, base_metadata, gpuaddr;
};
_Static_assert(sizeof(struct priv_handle) == 112, "private_handle_t layout changed");
#define PRIV_MAGIC 0x676d736d /* 'gmsm' */

/*
 * The ISP needs a request applied before every SOF. Submitting a single
 * request makes it bubble at the first EPOCH ("No available request for
 * Apply"), so keep NBUF requests in flight and hand back each buffer as
 * soon as its result arrives. Dumping a late frame also gives 3A time to
 * converge - the first frames come out black regardless of the pipeline.
 */
#define NBUF         6
#define TARGET_FRAME 200

/*
 * NV12 out of the IPE is not packed: the luma plane is padded to an aligned
 * number of scanlines and chroma starts there, not at width*height. Measured
 * on this target: 1280x720 puts chroma at row 768 = align(720, 64), while
 * 1280x960 needs no padding. Sizing the buffer as width*height*3/2 both
 * truncates the chroma plane and makes the HAL return the buffer with
 * CAMERA3_BUFFER_STATUS_ERROR.
 */
#define ALIGN_UP(x, a) (((x) + (a) - 1) & ~((a) - 1))

struct slot {
	int    fd;
	size_t size;
	void  *map;                       /* kept mapped in streaming mode */
	struct priv_handle ph;
	void  *handle;                    /* buffer_handle_t; &handle is what HAL takes */
	struct camera3_stream_buffer sb;
};
static struct slot g_slots[NBUF];

static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t  g_cond = PTHREAD_COND_INITIALIZER;
static int g_ready[NBUF];                 /* slot index -> result arrived */
static uint32_t g_ready_frame[NBUF];
static int g_ready_status[NBUF], g_ready_fence[NBUF];
static int g_nready;

/*
 * A release fence, when the HAL hands one back, is an owned fd: the buffer
 * contents are undefined until it signals and the fd leaks unless we close it.
 * CamX returns -1 here in practice - it completes synchronously - but a plain
 * "-1 means nothing to do" is the only part of that worth relying on.
 */
__attribute__((unused)) static void consume_release_fence(int fd)
{
	if (fd < 0)
		return;
	struct pollfd pfd = { .fd = fd, .events = POLLIN };
	int rc;
	do {
		rc = poll(&pfd, 1, 2000);
	} while (rc < 0 && errno == EINTR);
	if (rc == 0)
		fprintf(stderr, "release fence %d still unsignalled after 2s\n", fd);
	else if (rc < 0)
		perror("poll(release_fence)");
	close(fd);
}

static void on_result(const struct camera3_callback_ops *cb,
		      const struct camera3_capture_result *r)
{
	(void)cb;
	if (!r || r->num_output_buffers == 0)
		return;                   /* metadata-only partial result */
	pthread_mutex_lock(&g_lock);
	for (uint32_t i = 0; i < r->num_output_buffers; i++) {
		for (int k = 0; k < NBUF; k++) {
			if (r->output_buffers[i].buffer == &g_slots[k].handle) {
				g_ready[k] = 1;
				g_ready_frame[k] = r->frame_number;
				g_ready_status[k] = r->output_buffers[i].status;
				g_ready_fence[k] = r->output_buffers[i].release_fence;
				g_nready++;
			}
		}
	}
	pthread_cond_signal(&g_cond);
	pthread_mutex_unlock(&g_lock);
}
struct camera3_notify_msg {
	int type;                         /* 1 = ERROR, 2 = SHUTTER */
	union {
		struct { uint32_t frame_number; struct camera3_stream *stream; int code; } error;
		struct { uint32_t frame_number; uint64_t timestamp; } shutter;
	} m;
};

static void on_notify(const struct camera3_callback_ops *cb, const void *msg)
{
	(void)cb;
	const struct camera3_notify_msg *n = msg;
	if (!n || n->type != 1)
		return;
	static const char *code[] = { "?", "DEVICE", "REQUEST", "RESULT", "BUFFER" };
	int c = n->m.error.code;
	fprintf(stderr, "  NOTIFY ERROR frame %u code %d (%s) stream %p\n",
		n->m.error.frame_number, c,
		(c >= 1 && c <= 4) ? code[c] : "?", (void *)n->m.error.stream);
}

__attribute__((unused)) static int dma_alloc(size_t len)
{
	int heap = open(DMA_HEAP, O_RDONLY | O_CLOEXEC);
	if (heap < 0) { perror("open dma_heap"); return -1; }
	struct dma_heap_allocation_data d = { .len = len, .fd_flags = O_RDWR | O_CLOEXEC };
	if (ioctl(heap, DMA_HEAP_IOCTL_ALLOC, &d) < 0) { perror("DMA_HEAP_ALLOC"); close(heap); return -1; }
	close(heap);
	return (int)d.fd;
}

/*
 * ---- camera_metadata blob layout ----
 *
 * construct_default_request_settings() hands back a read-only blob. Rather
 * than link libcamera_metadata, walk the on-disk layout directly: a header,
 * an array of fixed-size entries at entries_start, and a data pool at
 * data_start. Values of 4 bytes or less live inline in the entry.
 *
 * Only values of already-present entries are patched, never the entry count,
 * so the blob never has to grow and its offsets all stay valid.
 */
struct cam_meta {
	uint32_t size, version, flags;
	uint32_t entry_count, entry_capacity;
	uint32_t entries_start;
	uint32_t data_count, data_capacity;
	uint32_t data_start;
	uint32_t padding;
	uint64_t vendor_id;
};

struct cam_meta_entry {
	uint32_t tag;
	uint32_t count;
	union { uint32_t offset; uint8_t value[4]; } data;
	uint8_t  type;
	uint8_t  reserved[3];
};
_Static_assert(sizeof(struct cam_meta_entry) == 16, "metadata entry layout");

__attribute__((unused)) static const char *meta_type_name(uint8_t t)
{
	static const char *n[] = { "byte", "int32", "float", "int64", "double", "rational" };
	return t < 6 ? n[t] : "?";
}
static const uint8_t meta_type_size[] = { 1, 4, 4, 8, 8, 8 };

static struct cam_meta_entry *meta_entries(const void *blob)
{
	const struct cam_meta *m = blob;
	return (struct cam_meta_entry *)((uint8_t *)blob + m->entries_start);
}

/* Where an entry's payload actually lives: inline for <=4 bytes, else pool. */
static uint8_t *meta_payload(void *blob, struct cam_meta_entry *e)
{
	const struct cam_meta *m = blob;
	size_t bytes = (size_t)e->count * meta_type_size[e->type < 6 ? e->type : 0];
	if (bytes <= 4)
		return e->data.value;
	return (uint8_t *)blob + m->data_start + e->data.offset;
}

__attribute__((unused)) static void meta_dump_n(const void *blob, uint32_t maxvals)
{
	const struct cam_meta *m = blob;
	printf("metadata: size=%u entries=%u/%u data=%u/%u entries@%u data@%u\n",
	       m->size, m->entry_count, m->entry_capacity,
	       m->data_count, m->data_capacity, m->entries_start, m->data_start);

	struct cam_meta_entry *e = meta_entries(blob);
	for (uint32_t i = 0; i < m->entry_count; i++) {
		if (e[i].type >= 6) { printf("  [%02u] tag=0x%08x BAD type %u\n", i, e[i].tag, e[i].type); continue; }
		uint8_t *p = meta_payload((void *)blob, &e[i]);
		printf("  [%02u] tag=0x%08x %-8s x%-3u ", i, e[i].tag, meta_type_name(e[i].type), e[i].count);
		for (uint32_t k = 0; k < e[i].count && k < maxvals; k++) {
			switch (e[i].type) {
			case 0: printf("%u ",   ((uint8_t  *)p)[k]); break;
			case 1: printf("%d ",   ((int32_t  *)p)[k]); break;
			case 2: printf("%g ",   ((float    *)p)[k]); break;
			case 3: printf("%lld ", (long long)((int64_t *)p)[k]); break;
			case 4: printf("%g ",   ((double   *)p)[k]); break;
			case 5: printf("%d/%d ", ((int32_t *)p)[2*k], ((int32_t *)p)[2*k+1]); break;
			}
		}
		if (e[i].count > maxvals) printf("...");
		printf("\n");
	}
}

/*
 * Patch value[0] of an existing entry. Returns 0 on success, -1 if absent.
 *
 * Takes the value as a double so FLOAT entries can be set too - manual focus
 * (ANDROID_LENS_FOCUS_DISTANCE) is a float, and without it the lens can only
 * be driven by the AF algorithm.
 */
__attribute__((unused)) static int meta_set(void *blob, uint32_t tag, double val)
{
	struct cam_meta *m = blob;
	struct cam_meta_entry *e = meta_entries(blob);
	for (uint32_t i = 0; i < m->entry_count; i++) {
		if (e[i].tag != tag || e[i].type >= 6)
			continue;
		uint8_t *p = meta_payload(blob, &e[i]);
		switch (e[i].type) {
		case 0: *(uint8_t *)p = (uint8_t)val;  break;
		case 1: *(int32_t *)p = (int32_t)val;  break;
		case 2: *(float *)p   = (float)val;    break;
		case 3: *(int64_t *)p = (int64_t)val;  break;
		case 4: *(double *)p  = val;           break;
		default: return -1;
		}
		printf("  meta_set tag=0x%08x (%s) = %g\n",
		       tag, meta_type_name(e[i].type), val);
		return 0;
	}
	fprintf(stderr, "  meta_set tag=0x%08x NOT PRESENT\n", tag);
	return -1;
}

#endif /* CAMX_HAL_H */
