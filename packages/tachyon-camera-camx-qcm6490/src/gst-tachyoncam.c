/*
 * gst-tachyoncam - GStreamer tracer that fixes two things in the desktop camera
 * apps (Snapshot, Cheese), neither of which they expose a setting for:
 *
 * - vp8enc: they only record VP8, and its defaults (256 kbps, one thread)
 *   reach ~10 fps at 1080p here; realtime mode on every core holds 30 fps at
 *   6 Mbps.
 * - pipewiresrc: PipeWire 1.0.5 withdraws a buffer mapping while downstream
 *   still reads it, so taking a photo or stopping a recording crashes in
 *   gst_video_frame_copy. always-copy hands downstream a private copy, with no
 *   change to the system's libgstpipewire.so.
 *
 * Loaded through GST_TRACERS=tachyoncam (src/90-tachyon-camera.conf).
 *
 * Like camx-hal.h it declares the small GStreamer 1.x ABI it uses instead of
 * needing arm64 headers in the cross build; the symbols resolve against the
 * libraries of the process loading it. Built by build-assets.sh.
 */
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

typedef unsigned long GType;
typedef int gboolean;
typedef unsigned long long GstClockTime;
typedef void (*GCallback)(void);

typedef struct {
	GType type;
	const char *type_name;
	unsigned int class_size;
	unsigned int instance_size;
} GTypeQuery;

typedef gboolean (*GstPluginInitFunc)(void *plugin);

typedef struct {
	int major_version;
	int minor_version;
	const char *name;
	const char *description;
	GstPluginInitFunc plugin_init;
	const char *version;
	const char *license;
	const char *source;
	const char *package;
	const char *origin;
	const char *release_datetime;
	void *_gst_reserved[4];
} GstPluginDesc;
_Static_assert(sizeof(GstPluginDesc) == 112, "GstPluginDesc layout changed");
_Static_assert(offsetof(GstPluginDesc, plugin_init) == 24, "GstPluginDesc layout changed");
_Static_assert(sizeof(GTypeQuery) == 24, "GTypeQuery layout changed");

GType gst_tracer_get_type(void);
gboolean gst_tracer_register(void *plugin, const char *name, GType type);
void gst_tracing_register_hook(void *tracer, const char *detail, GCallback func);
void gst_util_set_object_arg(void *object, const char *name, const char *value);
void g_type_query(GType type, GTypeQuery *query);
GType g_type_register_static_simple(GType parent, const char *name,
		unsigned int class_size, void *class_init,
		unsigned int instance_size, void (*instance_init)(void *, void *),
		int flags);
const char *g_type_name_from_instance(void *instance);
void *g_object_class_find_property(void *klass, const char *name);

/* Skip a property a later vp8enc drops rather than warn on every pipeline
 * (a GObject's first field is its class pointer). */
static void set_prop(void *obj, const char *name, const char *value)
{
	if (g_object_class_find_property(*(void **)obj, name))
		gst_util_set_object_arg(obj, name, value);
}

static void on_element_new(void *tracer, GstClockTime ts, void *element)
{
	const char *type = g_type_name_from_instance(element);
	char threads[16];

	(void)tracer; (void)ts;
	if (!strcmp(type, "GstPipeWireSrc")) {
		set_prop(element, "always-copy", "true");
		return;
	}
	if (strcmp(type, "GstVP8Enc"))
		return;
	snprintf(threads, sizeof(threads), "%ld", sysconf(_SC_NPROCESSORS_ONLN));
	set_prop(element, "deadline", "1");
	set_prop(element, "cpu-used", "8");
	set_prop(element, "threads", threads);
	set_prop(element, "token-partitions", "3");
	set_prop(element, "end-usage", "cbr");
	set_prop(element, "target-bitrate", "6000000");
}

static void tracer_init(void *instance, void *klass)
{
	(void)klass;
	gst_tracing_register_hook(instance, "element-new", (GCallback)on_element_new);
}

static gboolean plugin_init(void *plugin)
{
	GTypeQuery q;
	GType type;

	/* No fields of our own, so the subclass is exactly the parent's size. */
	g_type_query(gst_tracer_get_type(), &q);
	type = g_type_register_static_simple(q.type, "TachyonCamTracer",
			q.class_size, NULL, q.instance_size, tracer_init, 0);
	return gst_tracer_register(plugin, "tachyoncam", type);
}

/* 1.24 is the ABI checked above; GStreamer refuses a newer minor than its own. */
static const GstPluginDesc desc = {
	1, 24, "tachyoncam", "vp8enc and pipewiresrc tuning for Tachyon camera apps", plugin_init,
	"1.0", "LGPL", "tachyon-camera-camx-qcm6490", "tachyon-camera-camx-qcm6490",
	"https://www.particle.io", NULL, { NULL },
};

/* The name the loader derives from libgsttachyoncam.so. */
__attribute__((visibility("default"))) const GstPluginDesc *gst_plugin_tachyoncam_get_desc(void)
{
	return &desc;
}
