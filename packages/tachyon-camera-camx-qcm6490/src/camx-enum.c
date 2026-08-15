/*
 * camx-enum - minimal CamX HAL module enumerator for QCM6490 bring-up (G1 gate).
 *
 * Loads the CamX HAL and calls only get_number_of_cameras() and
 * get_camera_info(). No streams, no buffers, no metadata parsing, so it needs
 * neither gralloc/gbm nor the Android support libraries the vendor test tool
 * pulls in - plain C against the system libc is enough.
 *
 * The HAL structs are declared here rather than included: camx-kt-dev ships
 * hardware/camera_common.h but not the hardware.h that defines hw_module_t.
 * Layout was taken from the shipped binary (HMI in .data) and is checked at
 * runtime via the tag field before any function pointer is used.
 *
 * Build:
 *   aarch64-linux-gnu-gcc -O2 -o camx-enum camx-enum.c -ldl
 */

#include <dlfcn.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>

#define HAL_PATH            "/usr/lib/hw/camera.qcom.so"
#define HAL_SYM             "HMI"
#define HARDWARE_MODULE_TAG 0x48574d54u   /* 'HWMT' */

/* Android hw_module_t, LP64. sizeof must be 248 - asserted below. */
struct hw_module {
	uint32_t     tag;
	uint16_t     module_api_version;
	uint16_t     hal_api_version;
	const char  *id;
	const char  *name;
	const char  *author;
	void        *methods;
	void        *dso;
	uint64_t     reserved[25];
};

struct camera_info {
	int          facing;
	int          orientation;
	uint32_t     device_version;
	const void  *static_camera_characteristics;
	int          resource_cost;
	char       **conflicting_devices;
	size_t       conflicting_devices_length;
};

struct camera_module {
	struct hw_module common;
	int  (*get_number_of_cameras)(void);
	int  (*get_camera_info)(int camera_id, struct camera_info *info);
	/* Remaining entries are unused here and deliberately left out. */
};

/* If this fires the struct no longer matches the binary and every function
 * pointer below would be read from the wrong offset. */
_Static_assert(sizeof(struct hw_module) == 248, "hw_module_t layout changed");
_Static_assert(offsetof(struct camera_module, get_number_of_cameras) == 248,
	       "camera_module_t layout changed");

static const char *facing_str(int f)
{
	switch (f) {
	case 0:  return "BACK";
	case 1:  return "FRONT";
	case 2:  return "EXTERNAL";
	default: return "?";
	}
}

int main(int argc, char **argv)
{
	/* The kt stack installs the HAL flat under /usr/lib/hw, the older
	 * per-SoC packaging puts it in /usr/lib/<soc>/hw - allow either. */
	const char *path = (argc > 1) ? argv[1] : HAL_PATH;

	void *lib = dlopen(path, RTLD_NOW);
	if (!lib) {
		fprintf(stderr, "dlopen(%s) failed: %s\n", path, dlerror());
		return 1;
	}
	printf("hal        : %s\n", path);

	struct camera_module *mod = dlsym(lib, HAL_SYM);
	if (!mod) {
		fprintf(stderr, "dlsym(%s) failed: %s\n", HAL_SYM, dlerror());
		return 1;
	}

	if (mod->common.tag != HARDWARE_MODULE_TAG) {
		fprintf(stderr, "bad module tag 0x%08x (expected 0x%08x) - "
			"struct layout does not match this HAL\n",
			mod->common.tag, HARDWARE_MODULE_TAG);
		return 1;
	}

	printf("module     : %s (%s)\n",
	       mod->common.name ? mod->common.name : "?",
	       mod->common.id ? mod->common.id : "?");
	printf("author     : %s\n", mod->common.author ? mod->common.author : "?");
	printf("module_api : 0x%04x\n", mod->common.module_api_version);
	printf("hal_api    : 0x%04x\n", mod->common.hal_api_version);

	if (!mod->get_number_of_cameras) {
		fprintf(stderr, "get_number_of_cameras is NULL\n");
		return 1;
	}

	int n = mod->get_number_of_cameras();
	printf("cameras    : %d\n", n);
	if (n <= 0) {
		fprintf(stderr, "no cameras enumerated\n");
		return 2;
	}

	if (!mod->get_camera_info) {
		fprintf(stderr, "get_camera_info is NULL\n");
		return 1;
	}

	/* Ids are not necessarily 0..n-1: the TPG modules declare 10 and 11,
	 * so probe a range wide enough to cover them and report what answers. */
	int found = 0;
	for (int id = 0; id < 32; id++) {
		struct camera_info info;
		int rc;

		__builtin_memset(&info, 0, sizeof(info));
		rc = mod->get_camera_info(id, &info);
		if (rc != 0)
			continue;

		found++;
		printf("  id %-2d  facing=%-8s orientation=%-3d device_version=0x%04x "
		       "resource_cost=%d static_meta=%s\n",
		       id, facing_str(info.facing), info.orientation,
		       info.device_version, info.resource_cost,
		       info.static_camera_characteristics ? "yes" : "NULL");
	}

	printf("probed ids responding: %d\n", found);
	return found > 0 ? 0 : 2;
}
