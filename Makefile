MAKEFLAGS += -rR
.SUFFIXES:

DOCKER_IMAGE ?= tachyon-rootfs-overlay-builder
DOCKER_TAG ?= 1.0
DOCKER_REF := $(DOCKER_IMAGE):$(DOCKER_TAG)
DOCKER_STAMP := .tmp/.docker-build-$(DOCKER_TAG)

ROOTFS_SIZE_MB ?= auto
ROOT_PARTITION ?=
ROOTFS_OUTPUT := $(if $(strip $(OUTPUT_IMAGE)),$(OUTPUT_IMAGE),output/rootfs-custom.ext4)
KERNEL_OUTPUT := $(if $(strip $(OUTPUT_IMAGE)),$(OUTPUT_IMAGE),output/rootfs-with-kernel.ext4)

.PHONY: apply-rootfs apply-kernel docker-build setup-qemu test clean help

$(DOCKER_STAMP): Dockerfile scripts/apply-rootfs.sh scripts/install-kernel.sh
	@mkdir -p "$(dir $@)"
	docker build --network=host -t "$(DOCKER_REF)" .
	@touch "$@"

docker-build: $(DOCKER_STAMP)

setup-qemu:
	@arch="$$(uname -m)"; \
	if { [ "$$arch" = x86_64 ] || [ "$$arch" = amd64 ]; } \
	   && [ ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then \
		echo "Registering QEMU arm64 binfmt..."; \
		docker run --rm --privileged multiarch/qemu-user-static --reset -p yes; \
	fi

apply-rootfs: docker-build setup-qemu
	@test -n "$(INPUT_IMAGE)" || { echo "ERROR: INPUT_IMAGE is required" >&2; exit 1; }
	@test -f "$(INPUT_IMAGE)" || { echo "ERROR: INPUT_IMAGE not found: $(INPUT_IMAGE)" >&2; exit 1; }
	@test -n "$(STACK)" || { echo "ERROR: STACK is required" >&2; exit 1; }
	@test -f "stacks/$(STACK).json" || { echo "ERROR: stack not found: stacks/$(STACK).json" >&2; exit 1; }
	@mkdir -p "$(dir $(ROOTFS_OUTPUT))"
	docker run --rm --privileged --network=host \
		-e ACTION=overlay \
		-e INPUT_IMAGE=/input/source-image \
		-e OUTPUT_IMAGE=/output/$(notdir $(ROOTFS_OUTPUT)) \
		-e STACK="$(STACK)" \
		-e ROOTFS_SIZE_MB="$(ROOTFS_SIZE_MB)" \
		$(if $(strip $(ROOT_PARTITION)),-e ROOT_PARTITION="$(ROOT_PARTITION)") \
		-v "$(abspath $(INPUT_IMAGE)):/input/source-image:ro" \
		-v "$(abspath $(dir $(ROOTFS_OUTPUT))):/output" \
		-v /dev:/dev \
		-v "$(CURDIR)/overlays:/workspace/overlays:ro" \
		-v "$(CURDIR)/stacks:/workspace/stacks:ro" \
		"$(DOCKER_REF)"

apply-kernel: docker-build setup-qemu
	@test -n "$(INPUT_IMAGE)" || { echo "ERROR: INPUT_IMAGE is required" >&2; exit 1; }
	@test -f "$(INPUT_IMAGE)" || { echo "ERROR: INPUT_IMAGE not found: $(INPUT_IMAGE)" >&2; exit 1; }
	@test -n "$(KERNEL_IMAGE_DEB)" || { echo "ERROR: KERNEL_IMAGE_DEB is required" >&2; exit 1; }
	@test -f "$(KERNEL_IMAGE_DEB)" || { echo "ERROR: KERNEL_IMAGE_DEB not found: $(KERNEL_IMAGE_DEB)" >&2; exit 1; }
	@test -n "$(KERNEL_MODULES_DEB)" || { echo "ERROR: KERNEL_MODULES_DEB is required" >&2; exit 1; }
	@test -f "$(KERNEL_MODULES_DEB)" || { echo "ERROR: KERNEL_MODULES_DEB not found: $(KERNEL_MODULES_DEB)" >&2; exit 1; }
	@test -n "$(KERNEL_HEADERS_DEB)" || { echo "ERROR: KERNEL_HEADERS_DEB is required" >&2; exit 1; }
	@test -f "$(KERNEL_HEADERS_DEB)" || { echo "ERROR: KERNEL_HEADERS_DEB not found: $(KERNEL_HEADERS_DEB)" >&2; exit 1; }
	@test -n "$(KERNEL_COMMON_HEADERS_DEB)" || { echo "ERROR: KERNEL_COMMON_HEADERS_DEB is required" >&2; exit 1; }
	@test -f "$(KERNEL_COMMON_HEADERS_DEB)" || { echo "ERROR: KERNEL_COMMON_HEADERS_DEB not found: $(KERNEL_COMMON_HEADERS_DEB)" >&2; exit 1; }
	@mkdir -p "$(dir $(KERNEL_OUTPUT))"
	docker run --rm --privileged --network=host \
		-e ACTION=kernel \
		-e INPUT_IMAGE=/input/source-image \
		-e KERNEL_IMAGE_DEB=/input/kernel/image.deb \
		-e KERNEL_MODULES_DEB=/input/kernel/modules.deb \
		-e KERNEL_HEADERS_DEB=/input/kernel/headers.deb \
		-e KERNEL_COMMON_HEADERS_DEB=/input/kernel/common-headers.deb \
		-e OUTPUT_IMAGE=/output/$(notdir $(KERNEL_OUTPUT)) \
		-e ROOTFS_SIZE_MB="$(ROOTFS_SIZE_MB)" \
		$(if $(strip $(ROOT_PARTITION)),-e ROOT_PARTITION="$(ROOT_PARTITION)") \
		-v "$(abspath $(INPUT_IMAGE)):/input/source-image:ro" \
		-v "$(abspath $(KERNEL_IMAGE_DEB)):/input/kernel/image.deb:ro" \
		-v "$(abspath $(KERNEL_MODULES_DEB)):/input/kernel/modules.deb:ro" \
		-v "$(abspath $(KERNEL_HEADERS_DEB)):/input/kernel/headers.deb:ro" \
		-v "$(abspath $(KERNEL_COMMON_HEADERS_DEB)):/input/kernel/common-headers.deb:ro" \
		-v "$(abspath $(dir $(KERNEL_OUTPUT))):/output" \
		-v /dev:/dev \
		"$(DOCKER_REF)"

test: docker-build
	tests/test-camera-notify-ready.sh
	DOCKER_REF="$(DOCKER_REF)" tests/test-apply-rootfs.sh

clean:
	rm -rf .tmp output

help:
	@echo "Modify an existing Tachyon rootfs image"
	@echo
	@echo "Usage:"
	@echo "  make apply-rootfs INPUT_IMAGE=/path/rootfs.ext4 STACK=custom-rootfs [OUTPUT_IMAGE=output/rootfs-custom.ext4]"
	@echo "  make apply-kernel INPUT_IMAGE=/path/rootfs.ext4 KERNEL_IMAGE_DEB=/path/linux-image.deb \\"
	@echo "      KERNEL_MODULES_DEB=/path/linux-modules.deb KERNEL_HEADERS_DEB=/path/linux-headers.deb \\"
	@echo "      KERNEL_COMMON_HEADERS_DEB=/path/linux-common-headers.deb [OUTPUT_IMAGE=output/rootfs-with-kernel.ext4]"
	@echo
	@echo "Inputs: raw ext4, partitioned .img, or either format compressed as .xz"
	@echo "The input is mounted read-only; the result is always a new raw ext4 image."
	@echo
	@echo "Optional:"
	@echo "  ROOTFS_SIZE_MB=auto|<MiB>   Output size (default: auto)"
	@echo "  ROOT_PARTITION=<number>     Select a partition when auto-detection is ambiguous"
