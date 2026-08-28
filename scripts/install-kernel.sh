#!/usr/bin/env bash
# Install one complete Ubuntu kernel package closure into a rootfs.
#
# This intentionally requires four explicit debs. Ubuntu splits this kernel
# into image, modules, flavour headers and common headers. Installing only the
# image was previously made to "work" with --force-overwrite, but left the
# official linux-modules payload beside the locally built kernel. That mixed
# .ko/.ko.zst tree caused 206 split-BTF failures and let stale Venus aliases
# compete with Iris. A production image must replace the package ownership as
# a coherent set; force-overwrite is therefore neither needed nor allowed.
set -euo pipefail

IMAGE_DEB="${1:?usage: install-kernel <image.deb> <modules.deb> <headers.deb> <common-headers.deb>}"
MODULES_DEB="${2:?usage: install-kernel <image.deb> <modules.deb> <headers.deb> <common-headers.deb>}"
HEADERS_DEB="${3:?usage: install-kernel <image.deb> <modules.deb> <headers.deb> <common-headers.deb>}"
COMMON_HEADERS_DEB="${4:?usage: install-kernel <image.deb> <modules.deb> <headers.deb> <common-headers.deb>}"

export DEBIAN_FRONTEND=noninteractive
export TMPDIR=/tmp

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

declare -A DEB PKG VER ARCH
DEB[image]="${IMAGE_DEB}"
DEB[modules]="${MODULES_DEB}"
DEB[headers]="${HEADERS_DEB}"
DEB[common_headers]="${COMMON_HEADERS_DEB}"

for role in image modules headers common_headers; do
    [ -f "${DEB[$role]}" ] || die "$role deb not found: ${DEB[$role]}"
    dpkg-deb --info "${DEB[$role]}" >/dev/null 2>&1 \
        || die "$role is not a valid deb: ${DEB[$role]}"
    PKG[$role]="$(dpkg-deb -f "${DEB[$role]}" Package)"
    VER[$role]="$(dpkg-deb -f "${DEB[$role]}" Version)"
    ARCH[$role]="$(dpkg-deb -f "${DEB[$role]}" Architecture)"
done

case "${PKG[image]}" in
    linux-image-unsigned-*) KVER="${PKG[image]#linux-image-unsigned-}" ;;
    linux-image-*) KVER="${PKG[image]#linux-image-}" ;;
    *) die "expected a linux-image package, got ${PKG[image]}" ;;
esac

[ "${PKG[modules]}" = "linux-modules-${KVER}" ] \
    || die "modules package is ${PKG[modules]}, expected linux-modules-${KVER}"
[ "${PKG[headers]}" = "linux-headers-${KVER}" ] \
    || die "headers package is ${PKG[headers]}, expected linux-headers-${KVER}"
case "${PKG[common_headers]}" in
    linux-*-headers-[0-9]*) ;;
    *) die "unexpected common headers package: ${PKG[common_headers]}" ;;
esac

# All four packages must come from the same dpkg-buildpackage transaction.
# Matching only uname -r is insufficient because Ubuntu keeps the ABI release
# in the package name while the package revision distinguishes rebuilt content.
for role in modules headers common_headers; do
    [ "${VER[$role]}" = "${VER[image]}" ] \
        || die "$role version ${VER[$role]} differs from image ${VER[image]}"
done

ROOTFS_ARCH="$(dpkg --print-architecture)"
for role in image modules headers; do
    [ "${ARCH[$role]}" = "${ROOTFS_ARCH}" ] \
        || die "$role architecture ${ARCH[$role]} does not match rootfs ${ROOTFS_ARCH}"
done
[ "${ARCH[common_headers]}" = all ] \
    || die "common headers architecture must be all, got ${ARCH[common_headers]}"

image_deps="$(dpkg-deb -f "${IMAGE_DEB}" Depends)"
headers_deps="$(dpkg-deb -f "${HEADERS_DEB}" Depends)"
printf '%s\n' "${image_deps}" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*(.*$//' \
    | grep -Fxq "${PKG[modules]}" \
    || die "${PKG[image]} does not depend on ${PKG[modules]}"
printf '%s\n' "${headers_deps}" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*(.*$//' \
    | grep -Fxq "${PKG[common_headers]}" \
    || die "${PKG[headers]} does not depend on ${PKG[common_headers]}"

printf 'Installing kernel closure for %s, package version %s:\n' "${KVER}" "${VER[image]}"
for role in image modules headers common_headers; do
    printf '  %-14s %s (%s)\n' "$role" "${PKG[$role]}" "${ARCH[$role]}"
done

apt-get -o Acquire::Languages=none update

# dpkg -i/apt install clears a previous hold, so unhold before the transaction
# and apply the hold only after every package and postinst has succeeded. The
# locally rebuilt packages intentionally reuse Ubuntu's package names; without
# the hold a later apt upgrade could silently restore official kernel content.
package_names=(
    "${PKG[image]}"
    "${PKG[modules]}"
    "${PKG[headers]}"
    "${PKG[common_headers]}"
)

# The base desktop image also carries moving Particle meta packages. Holding
# only this ABI's four concrete packages would still let a future meta upgrade
# install a new official ABI and repoint the unversioned boot links. Add only
# meta packages that are actually installed; images without them stay valid.
for meta in \
    linux-particle \
    linux-particle-6.8 \
    linux-image-particle \
    linux-image-particle-6.8 \
    linux-headers-particle \
    linux-headers-particle-6.8; do
    if [ "$(dpkg-query -W -f='${db:Status-Status}' "$meta" 2>/dev/null || true)" = installed ]; then
        package_names+=("$meta")
    fi
done
apt-mark unhold "${package_names[@]}" >/dev/null 2>&1 || true
apt-get install -y --reinstall --no-install-recommends \
    "${IMAGE_DEB}" "${MODULES_DEB}" "${HEADERS_DEB}" "${COMMON_HEADERS_DEB}"

for role in image modules headers common_headers; do
    state="$(dpkg-query -W -f='${db:Status-Status} ${Version}' "${PKG[$role]}" 2>/dev/null || true)"
    [ "${state}" = "installed ${VER[$role]}" ] \
        || die "${PKG[$role]} state is '${state}', expected installed ${VER[$role]}"
done

[ -f "/boot/vmlinuz-${KVER}" ] \
    || die "kernel installation did not create /boot/vmlinuz-${KVER}"
[ -f "/boot/initrd.img-${KVER}" ] \
    || die "kernel installation did not create /boot/initrd.img-${KVER}"
[ -d "/lib/modules/${KVER}" ] \
    || die "kernel installation did not create /lib/modules/${KVER}"

# Reject the exact mixed-tree failure that motivated this workflow. The same
# relative module path must never exist once as .ko and once as .ko.zst.
duplicates="$(
    find "/lib/modules/${KVER}" -type f \( -name '*.ko' -o -name '*.ko.zst' \) -printf '%P\n' \
        | sed -E 's/\.ko(\.zst)?$//' | sort | uniq -d
)"
[ -z "${duplicates}" ] || { printf '%s\n' "${duplicates}" >&2; die "mixed .ko/.ko.zst module payload"; }

# The final kernel package owns Iris. An updates/ copy would outrank it through
# ubuntu.conf and put us back on an ABI-unsafe out-of-tree module.
[ ! -e "/lib/modules/${KVER}/updates/qcom-iris.ko" ] \
    || die "out-of-tree updates/qcom-iris.ko shadows the packaged Iris module"
modinfo -k "${KVER}" qcom_iris >/dev/null 2>&1 \
    || die "packaged qcom_iris module is unavailable for ${KVER}"
modinfo -k "${KVER}" v4l2loopback >/dev/null 2>&1 \
    || die "packaged v4l2loopback module is unavailable for ${KVER}"

depmod -a "${KVER}"

# Tachyon GRUB loads the unversioned paths. Kernel postinst does not reliably
# create these links in a qemu chroot, so make them deterministic here.
ln -sfn "vmlinuz-${KVER}" /boot/vmlinuz
ln -sfn "initrd.img-${KVER}" /boot/initrd.img

audit="$(dpkg --audit 2>&1)"
[ -z "${audit}" ] || { printf '%s\n' "${audit}" >&2; die "dpkg database is not clean"; }
apt-get check >/dev/null 2>&1 || die "apt-get check failed after kernel installation"

apt-mark hold "${package_names[@]}" >/dev/null
for package in "${package_names[@]}"; do
    apt-mark showhold | grep -Fxq "${package}" \
        || die "failed to hold ${package}"
done

printf 'Installed and held complete kernel closure; boot links target %s\n' "${KVER}"
