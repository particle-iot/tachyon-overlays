#!/usr/bin/env bash
set -euo pipefail

DOCKER_REF="${DOCKER_REF:-tachyon-rootfs-overlay-builder:1.0}"
TEST_DIR="$(mktemp -d /tmp/tachyon-rootfs-overlay-test.XXXXXX)"
trap 'rm -rf "${TEST_DIR}"' EXIT

mkdir -p \
    "${TEST_DIR}/rootfs/etc" \
    "${TEST_DIR}/rootfs/usr" \
    "${TEST_DIR}/rootfs/var" \
    "${TEST_DIR}/rootfs/tmp" \
    "${TEST_DIR}/workspace/overlays/add-test-marker/files" \
    "${TEST_DIR}/workspace/stacks" \
    "${TEST_DIR}/output"

printf 'original\n' > "${TEST_DIR}/rootfs/etc/base-marker"
printf 'LABEL=wrong-root / ext4 defaults 0 1\n' > "${TEST_DIR}/rootfs/etc/fstab"
printf 'overlay-applied\n' > "${TEST_DIR}/workspace/overlays/add-test-marker/files/rootfs-overlay-test"

cat > "${TEST_DIR}/workspace/overlays/add-test-marker/overlay.json" <<'JSON'
{
  "name": "add-test-marker",
  "description": "Test-only marker overlay.",
  "commands": [
    {
      "type": "copy-into-chroot",
      "source": "files/rootfs-overlay-test",
      "destination": "/etc/rootfs-overlay-test",
      "permissions": "644"
    }
  ]
}
JSON

cat > "${TEST_DIR}/workspace/stacks/test-rootfs.json" <<'JSON'
{
  "name": "test-rootfs",
  "description": "Test-only stack.",
  "steps": [
    { "type": "overlay", "name": "add-test-marker" }
  ]
}
JSON

docker run --rm --entrypoint bash \
    -v "${TEST_DIR}:/fixture" \
    "${DOCKER_REF}" -lc \
    'truncate -s 64M /fixture/input.ext4 && mkfs.ext4 -q -F -b 4096 -L test-rootfs -U 11111111-2222-3333-4444-555555555555 -d /fixture/rootfs /fixture/input.ext4'

INPUT_SHA="$(sha256sum "${TEST_DIR}/input.ext4" | awk '{print $1}')"

docker run --rm --privileged --network=host \
    -e INPUT_IMAGE=/input/source-image \
    -e OUTPUT_IMAGE=/output/result.ext4 \
    -e STACK=test-rootfs \
    -e ROOTFS_SIZE_MB=64 \
    -v "${TEST_DIR}/input.ext4:/input/source-image:ro" \
    -v "${TEST_DIR}/output:/output" \
    -v /dev:/dev \
    -v "${TEST_DIR}/workspace/overlays:/workspace/overlays:ro" \
    -v "${TEST_DIR}/workspace/stacks:/workspace/stacks:ro" \
    "${DOCKER_REF}"

OUTPUT="${TEST_DIR}/output/result.ext4"
[ -s "${OUTPUT}" ] || { echo "FAIL: output image missing" >&2; exit 1; }

AFTER_SHA="$(sha256sum "${TEST_DIR}/input.ext4" | awk '{print $1}')"
[ "${INPUT_SHA}" = "${AFTER_SHA}" ] || { echo "FAIL: input image was modified" >&2; exit 1; }

MARKER="$(docker run --rm --entrypoint debugfs -v "${OUTPUT}:/image:ro" "${DOCKER_REF}" -R 'cat /etc/rootfs-overlay-test' /image 2>/dev/null)"
[ "${MARKER}" = "overlay-applied" ] || { echo "FAIL: overlay marker missing from output" >&2; exit 1; }

FSTAB="$(docker run --rm --entrypoint debugfs -v "${OUTPUT}:/image:ro" "${DOCKER_REF}" -R 'cat /etc/fstab' /image 2>/dev/null)"
[ "${FSTAB}" = 'UUID=11111111-2222-3333-4444-555555555555 / ext4 defaults 0 1' ] \
    || { echo "FAIL: root fstab was not normalized to filesystem UUID" >&2; exit 1; }

META="$(docker run --rm --entrypoint blkid -v "${OUTPUT}:/image:ro" "${DOCKER_REF}" -s LABEL -s UUID -o export /image)"
printf '%s\n' "${META}" | grep -qx 'LABEL=test-rootfs'
printf '%s\n' "${META}" | grep -qx 'UUID=11111111-2222-3333-4444-555555555555'

docker run --rm --entrypoint e2fsck -v "${OUTPUT}:/image:ro" "${DOCKER_REF}" -fn /image >/dev/null

docker run --rm --entrypoint bash \
    -v "${TEST_DIR}:/fixture" \
    "${DOCKER_REF}" -lc '
        set -euo pipefail
        truncate -s 70M /fixture/partitioned.img
        printf "label: gpt\nstart=2048, size=131072, type=linux, name=system\n" \
            | sfdisk /fixture/partitioned.img >/dev/null
        dd if=/fixture/input.ext4 of=/fixture/partitioned.img \
            bs=512 seek=2048 conv=notrunc status=none
        xz -T0 -c /fixture/partitioned.img > /fixture/partitioned.img.xz
    '

PARTITIONED_SHA="$(sha256sum "${TEST_DIR}/partitioned.img.xz" | awk '{print $1}')"

docker run --rm --privileged --network=host \
    -e INPUT_IMAGE=/input/source-image \
    -e OUTPUT_IMAGE=/output/result-from-partitioned.ext4 \
    -e STACK=test-rootfs \
    -e ROOTFS_SIZE_MB=64 \
    -v "${TEST_DIR}/partitioned.img.xz:/input/source-image:ro" \
    -v "${TEST_DIR}/output:/output" \
    -v /dev:/dev \
    -v "${TEST_DIR}/workspace/overlays:/workspace/overlays:ro" \
    -v "${TEST_DIR}/workspace/stacks:/workspace/stacks:ro" \
    "${DOCKER_REF}"

PARTITIONED_OUTPUT="${TEST_DIR}/output/result-from-partitioned.ext4"
[ -s "${PARTITIONED_OUTPUT}" ] || { echo "FAIL: partitioned output image missing" >&2; exit 1; }
[ "${PARTITIONED_SHA}" = "$(sha256sum "${TEST_DIR}/partitioned.img.xz" | awk '{print $1}')" ] \
    || { echo "FAIL: compressed partitioned input was modified" >&2; exit 1; }

PARTITIONED_MARKER="$(docker run --rm --entrypoint debugfs -v "${PARTITIONED_OUTPUT}:/image:ro" "${DOCKER_REF}" -R 'cat /etc/rootfs-overlay-test' /image 2>/dev/null)"
[ "${PARTITIONED_MARKER}" = "overlay-applied" ] \
    || { echo "FAIL: overlay marker missing from partitioned-image output" >&2; exit 1; }

docker run --rm --entrypoint e2fsck -v "${PARTITIONED_OUTPUT}:/image:ro" "${DOCKER_REF}" -fn /image >/dev/null

mkdir -p "${TEST_DIR}/kernel-mocks" "${TEST_DIR}/boot"
touch \
    "${TEST_DIR}/image.deb" \
    "${TEST_DIR}/modules.deb" \
    "${TEST_DIR}/headers.deb" \
    "${TEST_DIR}/common-headers.deb"

cat > "${TEST_DIR}/kernel-mocks/dpkg-deb" <<'MOCK'
#!/usr/bin/env bash
if [ "${1:-}" = --info ]; then
    exit 0
fi
[ "${1:-}" = -f ] || exit 1
deb=$(basename "${2:-}")
field=${3:-}
case "$deb:$field" in
    image.deb:Package) echo linux-image-6.8.0-test-particle ;;
    image.deb:Version) echo 6.8.0-test.1 ;;
    image.deb:Architecture) echo arm64 ;;
    image.deb:Depends) echo 'linux-modules-6.8.0-test-particle, kmod' ;;
    modules.deb:Package) echo linux-modules-6.8.0-test-particle ;;
    modules.deb:Version) echo "${BAD_MODULE_VERSION:-6.8.0-test.1}" ;;
    modules.deb:Architecture) echo arm64 ;;
    headers.deb:Package) echo linux-headers-6.8.0-test-particle ;;
    headers.deb:Version) echo 6.8.0-test.1 ;;
    headers.deb:Architecture) echo arm64 ;;
    headers.deb:Depends) echo 'linux-particle-headers-6.8.0-test, libc6' ;;
    common-headers.deb:Package) echo linux-particle-headers-6.8.0-test ;;
    common-headers.deb:Version) echo 6.8.0-test.1 ;;
    common-headers.deb:Architecture) echo all ;;
    *) exit 1 ;;
esac
MOCK

cat > "${TEST_DIR}/kernel-mocks/dpkg" <<'MOCK'
#!/usr/bin/env bash
case "${1:-}" in
    --print-architecture) echo arm64 ;;
    --audit) exit 0 ;;
    *) exit 1 ;;
esac
MOCK

cat > "${TEST_DIR}/kernel-mocks/dpkg-query" <<'MOCK'
#!/usr/bin/env bash
package=${!#}
case "$package" in
    linux-image-6.8.0-test-particle|linux-modules-6.8.0-test-particle|linux-headers-6.8.0-test-particle|linux-particle-headers-6.8.0-test)
        case "$*" in
            *'${db:Status-Status} ${Version}'*) echo 'installed 6.8.0-test.1' ;;
            *) echo installed ;;
        esac ;;
    *) exit 1 ;;
esac
MOCK

cat > "${TEST_DIR}/kernel-mocks/apt-get" <<'MOCK'
#!/usr/bin/env bash
if printf '%s\n' "$@" | grep -qx install; then
    : > /boot/vmlinuz-6.8.0-test-particle
    : > /boot/initrd.img-6.8.0-test-particle
    mkdir -p /lib/modules/6.8.0-test-particle/kernel/drivers/media/platform/qcom/iris
    mkdir -p /lib/modules/6.8.0-test-particle/kernel/v4l2loopback
    : > /lib/modules/6.8.0-test-particle/kernel/drivers/media/platform/qcom/iris/qcom-iris.ko.zst
    : > /lib/modules/6.8.0-test-particle/kernel/v4l2loopback/v4l2loopback.ko.zst
fi
MOCK

cat > "${TEST_DIR}/kernel-mocks/apt-mark" <<'MOCK'
#!/usr/bin/env bash
case "${1:-}" in
    showhold)
        printf '%s\n' \
            linux-image-6.8.0-test-particle \
            linux-modules-6.8.0-test-particle \
            linux-headers-6.8.0-test-particle \
            linux-particle-headers-6.8.0-test ;;
esac
MOCK

cat > "${TEST_DIR}/kernel-mocks/modinfo" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK

cat > "${TEST_DIR}/kernel-mocks/depmod" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK

chmod +x "${TEST_DIR}/kernel-mocks/"*
docker run --rm --entrypoint /usr/bin/env \
    -v "${TEST_DIR}:/fixture" \
    -v "${TEST_DIR}/boot:/boot" \
    "${DOCKER_REF}" \
    PATH=/fixture/kernel-mocks:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    /usr/local/bin/install-kernel \
        /fixture/image.deb \
        /fixture/modules.deb \
        /fixture/headers.deb \
        /fixture/common-headers.deb

[ "$(readlink "${TEST_DIR}/boot/vmlinuz")" = vmlinuz-6.8.0-test-particle ] \
    || { echo "FAIL: kernel vmlinuz link is incorrect" >&2; exit 1; }
[ "$(readlink "${TEST_DIR}/boot/initrd.img")" = initrd.img-6.8.0-test-particle ] \
    || { echo "FAIL: kernel initrd link is incorrect" >&2; exit 1; }

# A same-uname-r modules package from another build is not a valid closure.
# The installer must reject it before apt mutates the image.
if docker run --rm --entrypoint /usr/bin/env \
    -e BAD_MODULE_VERSION=6.8.0-test.2 \
    -v "${TEST_DIR}:/fixture" \
    "${DOCKER_REF}" \
    PATH=/fixture/kernel-mocks:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    /usr/local/bin/install-kernel \
        /fixture/image.deb \
        /fixture/modules.deb \
        /fixture/headers.deb \
        /fixture/common-headers.deb; then
    echo "FAIL: mismatched kernel package versions were accepted" >&2
    exit 1
fi

echo "PASS: rootfs pipeline, immutable inputs, fsck gates, and coherent kernel closure"
