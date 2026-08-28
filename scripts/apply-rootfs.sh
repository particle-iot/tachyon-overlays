#!/usr/bin/env bash
set -euo pipefail

INPUT_IMAGE="${INPUT_IMAGE:?INPUT_IMAGE is required}"
OUTPUT_IMAGE="${OUTPUT_IMAGE:?OUTPUT_IMAGE is required}"
ACTION="${ACTION:-overlay}"
STACK="${STACK:-}"
KERNEL_IMAGE_DEB="${KERNEL_IMAGE_DEB:-}"
KERNEL_MODULES_DEB="${KERNEL_MODULES_DEB:-}"
KERNEL_HEADERS_DEB="${KERNEL_HEADERS_DEB:-}"
KERNEL_COMMON_HEADERS_DEB="${KERNEL_COMMON_HEADERS_DEB:-}"
ROOTFS_SIZE_MB="${ROOTFS_SIZE_MB:-auto}"
ROOT_PARTITION="${ROOT_PARTITION:-}"

OVERLAY_ROOT=/workspace
OVERLAY_ENGINE=/opt/tachyon-overlay-tool/overlay.py
WORK_DIR="$(mktemp -d /tmp/tachyon-rootfs-overlay.XXXXXX)"
ROOTFS_DIR="${WORK_DIR}/rootfs"
SOURCE_MOUNT="${WORK_DIR}/source"
DNS_BACKUP="${ROOTFS_DIR}/etc/resolv.conf.rootfs-overlay-backup"
DNS_INJECTED="${WORK_DIR}/resolv.conf.injected"

SOURCE_MOUNTED=0
SOURCE_LOOP=""
DNS_PREPARED=0
APT_HOOKS_DISABLED=0
OUTPUT_TMP=""

# chroot 里每跑一次 apt, 都会拖着一串 hook 一起跑: 重建 command-not-found
# 数据库, 刷新 appstream 索引, 通知 PackageKit / snapd / update-notifier。
# 这些全是给交互式桌面准备的, 造镜像时一点用都没有 —— 偏偏它们又都是 Python,
# 在 x86 上跑 arm64 要靠 qemu 逐条指令翻译。实测 cnf-update-db 一次就能占满
# 一个核跑掉 4 分钟, 而这套 hook 每装一批包就会再来一遍。
#
# 处理方式是进 chroot 前临时挪走, 出来之前原样放回去, 镜像内容不受影响。
# 跟下面 resolv.conf 的注入/恢复是同一个套路。
#
# 注意是挪到 apt.conf.d 外面, 不是在原地改名: apt 会扫整个目录, 对每个扩展名
# 不认识的文件都刷一行 "Ignoring file ... invalid filename extension", 每次
# apt 操作重复一遍。功能上无害, 但会把真正的日志淹掉。
APT_HOOK_NAMES=(
    50command-not-found     # cnf-update-db, 最贵的一个
    50appstream             # appstreamcli refresh
    99update-notifier       # 桌面更新提示, chroot 里根本没有桌面
    20packagekit            # 通知 PackageKit, 服务没在跑
    20snapd.conf            # 同上, snapd
    20apt-esm-hook.conf     # Ubuntu Pro ESM 提示
)
# 挪出去以后的暂存位置, 在 rootfs 之外, 收工时跟着 WORK_DIR 一起消失。
APT_HOOK_STASH="${WORK_DIR}/apt-hooks-stash"

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

unmount_chroot() {
    local path
    for path in dev/pts run sys proc dev; do
        if mountpoint -q "${ROOTFS_DIR}/${path}" 2>/dev/null; then
            umount "${ROOTFS_DIR}/${path}" 2>/dev/null || true
        fi
    done
}

restore_dns() {
    [ "${DNS_PREPARED}" -eq 1 ] || return 0

    if [ ! -L "${ROOTFS_DIR}/etc/resolv.conf" ] \
       && [ -f "${ROOTFS_DIR}/etc/resolv.conf" ] \
       && cmp -s "${DNS_INJECTED}" "${ROOTFS_DIR}/etc/resolv.conf"; then
        rm -f "${ROOTFS_DIR}/etc/resolv.conf"
        if [ -e "${DNS_BACKUP}" ] || [ -L "${DNS_BACKUP}" ]; then
            mv "${DNS_BACKUP}" "${ROOTFS_DIR}/etc/resolv.conf"
        fi
    else
        rm -f "${DNS_BACKUP}"
    fi
    rm -f "${DNS_INJECTED}"
    DNS_PREPARED=0
}

disable_apt_hooks() {
    local dir="${ROOTFS_DIR}/etc/apt/apt.conf.d" name
    [ -d "${dir}" ] || return 0

    mkdir -p "${APT_HOOK_STASH}"
    for name in "${APT_HOOK_NAMES[@]}"; do
        # 必须写成 if。`[ -f x ] && mv` 在文件不存在时整行返回 1,
        # set -e 会当场把脚本打死 —— 而"这个 hook 本来就没装"是正常情况。
        if [ -f "${dir}/${name}" ]; then
            mv "${dir}/${name}" "${APT_HOOK_STASH}/${name}"
        fi
    done
    APT_HOOKS_DISABLED=1
}

restore_apt_hooks() {
    [ "${APT_HOOKS_DISABLED}" -eq 1 ] || return 0

    local dir="${ROOTFS_DIR}/etc/apt/apt.conf.d" name
    for name in "${APT_HOOK_NAMES[@]}"; do
        [ -f "${APT_HOOK_STASH}/${name}" ] || continue
        # overlay 期间要是有包重新装了同名 hook, 那份是新的, 不能拿旧的盖回去,
        # 直接丢掉暂存的那份。
        if [ -e "${dir}/${name}" ]; then
            rm -f "${APT_HOOK_STASH}/${name}"
        else
            mv "${APT_HOOK_STASH}/${name}" "${dir}/${name}"
        fi
    done
    APT_HOOKS_DISABLED=0
}

release_source() {
    if [ "${SOURCE_MOUNTED}" -eq 1 ]; then
        umount "${SOURCE_MOUNT}" 2>/dev/null || true
        SOURCE_MOUNTED=0
    fi
    if [ -n "${SOURCE_LOOP}" ]; then
        partx -d "${SOURCE_LOOP}" 2>/dev/null || true
        losetup -d "${SOURCE_LOOP}" 2>/dev/null || true
        SOURCE_LOOP=""
    fi
}

cleanup() {
    local rc=$?
    set +e
    unmount_chroot
    restore_dns
    restore_apt_hooks
    release_source
    [ -n "${OUTPUT_TMP}" ] && rm -f "${OUTPUT_TMP}"
    rm -rf "${WORK_DIR}"
    exit "${rc}"
}
trap cleanup EXIT INT TERM

fsck_readonly() {
    local device="$1" rc=0
    e2fsck -fn "${device}" >/dev/null 2>&1 || rc=$?
    [ "${rc}" -lt 4 ] || die "input filesystem failed e2fsck validation (rc=${rc})"
}

fsck_repair_gate() {
    local image="$1" rc=0
    e2fsck -fy "${image}" || rc=$?
    [ "${rc}" -lt 4 ] || die "output filesystem failed e2fsck validation (rc=${rc})"
}

normalize_root_fstab() {
    local fstab="${ROOTFS_DIR}/etc/fstab"
    local rewritten="${WORK_DIR}/fstab.normalized"

    [ -f "${fstab}" ] || die "input rootfs has no /etc/fstab"
    [ -n "${FS_UUID}" ] || die "input rootfs has no UUID for /etc/fstab"

    # The released desktop image is labelled desktop-rootfs but its fstab
    # still says LABEL=cloudimg-rootfs. The kernel command line mounts / rw, so
    # the board appears usable while systemd-remount-fs fails on every boot.
    # Use the UUID that this pipeline also preserves on the output image; UUID
    # avoids a second naming contract between Composer, mkfs and this overlay.
    awk -v source="UUID=${FS_UUID}" '
        BEGIN { roots = 0 }
        /^# Root filesystem \(cloud-image ext4 label\)$/ {
            print "# Root filesystem (UUID normalized by Tachyon image builder)"
            next
        }
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { print; next }
        $2 == "/" { $1 = source; roots++ }
        { print }
        END { if (roots != 1) exit 42 }
    ' "${fstab}" > "${rewritten}" \
        || die "expected exactly one root mount in /etc/fstab"
    install -m 0644 "${rewritten}" "${fstab}"
    log "Normalized /etc/fstab root source to UUID=${FS_UUID}"
}

select_root_partition() {
    python3 - "${SOURCE_LOOP}" "${ROOT_PARTITION}" <<'PY'
import json
import subprocess
import sys

loopdev, requested = sys.argv[1:]
data = json.loads(subprocess.check_output([
    "lsblk", "-J", "-p", "-o", "PATH,TYPE,FSTYPE,LABEL,PARTLABEL", loopdev
], text=True))

parts = []
def walk(nodes):
    for node in nodes:
        if node.get("type") == "part":
            parts.append(node)
        walk(node.get("children") or [])
walk(data.get("blockdevices") or [])

for part in parts:
    if not part.get("fstype"):
        probe = subprocess.run(
            ["blkid", "-p", "-s", "TYPE", "-o", "value", part["path"]],
            text=True, capture_output=True,
        )
        if probe.returncode == 0:
            part["fstype"] = probe.stdout.strip()

if requested:
    if not requested.isdigit():
        sys.exit("ROOT_PARTITION must be a numeric partition number")
    suffix = "p" + requested if loopdev[-1].isdigit() else requested
    expected = loopdev + suffix
    matches = [p for p in parts if p.get("path") == expected]
    if len(matches) != 1:
        sys.exit(f"requested root partition does not exist: {expected}")
    print(expected)
    raise SystemExit(0)

ext4 = [p for p in parts if (p.get("fstype") or "").lower() == "ext4"]
preferred_labels = {"rootfs", "system", "system_a", "cloudimg-rootfs", "writable"}
preferred = [
    p for p in ext4
    if (p.get("label") or "").lower() in preferred_labels
    or (p.get("partlabel") or "").lower() in preferred_labels
]

if len(preferred) == 1:
    print(preferred[0]["path"])
elif len(preferred) > 1:
    choices = ", ".join(p["path"] for p in preferred)
    sys.exit(f"multiple labelled root partitions found ({choices}); set ROOT_PARTITION")
elif len(ext4) == 1:
    print(ext4[0]["path"])
elif not ext4:
    sys.exit("no ext4 partition found")
else:
    choices = ", ".join(p["path"] for p in ext4)
    sys.exit(f"multiple ext4 partitions found ({choices}); set ROOT_PARTITION")
PY
}

[ -f "${INPUT_IMAGE}" ] || die "input image not found: ${INPUT_IMAGE}"
case "${ACTION}" in
    overlay)
        [ -n "${STACK}" ] || die "STACK is required for overlay action"
        [[ "${STACK}" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid STACK name: ${STACK}"
        [ -f "${OVERLAY_ROOT}/stacks/${STACK}.json" ] || die "stack not found: ${STACK}"
        [ -f "${OVERLAY_ENGINE}" ] || die "overlay engine not found: ${OVERLAY_ENGINE}"
        ;;
    kernel)
        for kernel_deb in \
            "${KERNEL_IMAGE_DEB}" \
            "${KERNEL_MODULES_DEB}" \
            "${KERNEL_HEADERS_DEB}" \
            "${KERNEL_COMMON_HEADERS_DEB}"; do
            [ -f "${kernel_deb}" ] || die "kernel closure deb not found: ${kernel_deb:-<empty>}"
            dpkg-deb --info "${kernel_deb}" >/dev/null 2>&1 \
                || die "invalid kernel closure deb: ${kernel_deb}"
        done
        ;;
    *)
        die "unsupported ACTION: ${ACTION}"
        ;;
esac
case "${OUTPUT_IMAGE}" in
    /output/*) ;;
    *) die "OUTPUT_IMAGE must be under /output" ;;
esac
if [ "${ROOTFS_SIZE_MB}" != auto ] && ! [[ "${ROOTFS_SIZE_MB}" =~ ^[1-9][0-9]*$ ]]; then
    die "ROOTFS_SIZE_MB must be 'auto' or a positive integer"
fi

mkdir -p "${ROOTFS_DIR}" "${SOURCE_MOUNT}" "$(dirname "${OUTPUT_IMAGE}")"

SOURCE_IMAGE="${INPUT_IMAGE}"
INPUT_FILE_TYPE="$(file -b "${INPUT_IMAGE}" 2>/dev/null || true)"
if [[ "${INPUT_IMAGE}" = *.xz ]] || [[ "${INPUT_FILE_TYPE}" = *"XZ compressed data"* ]]; then
    SOURCE_IMAGE="${WORK_DIR}/source-image"
    log "Decompressing $(basename "${INPUT_IMAGE}")"
    xz -dc "${INPUT_IMAGE}" > "${SOURCE_IMAGE}"
fi

log "Detecting input image format"
FS_TYPE="$(blkid -p -s TYPE -o value "${SOURCE_IMAGE}" 2>/dev/null || true)"
SOURCE_LOOP="$(losetup -fP --show --read-only "${SOURCE_IMAGE}")"

if [ "${FS_TYPE}" = ext4 ]; then
    ROOT_DEVICE="${SOURCE_LOOP}"
    log "Input is a raw ext4 filesystem"
else
    partx -a "${SOURCE_LOOP}" 2>/dev/null || true
    ROOT_DEVICE="$(select_root_partition)" || die "could not select root partition"
    log "Selected root partition: ${ROOT_DEVICE}"
fi

[ -b "${ROOT_DEVICE}" ] || die "root filesystem device not available: ${ROOT_DEVICE}"
fsck_readonly "${ROOT_DEVICE}"

FS_LABEL="$(blkid -s LABEL -o value "${ROOT_DEVICE}" 2>/dev/null || true)"
FS_UUID="$(blkid -s UUID -o value "${ROOT_DEVICE}" 2>/dev/null || true)"
FS_LABEL="${FS_LABEL:-rootfs}"

log "Copying input rootfs (read-only source, LABEL=${FS_LABEL}, UUID=${FS_UUID:-new})"
mount -o ro "${ROOT_DEVICE}" "${SOURCE_MOUNT}"
SOURCE_MOUNTED=1
rsync -aHAX --numeric-ids "${SOURCE_MOUNT}/" "${ROOTFS_DIR}/"
release_source

for required in etc usr var; do
    [ -d "${ROOTFS_DIR}/${required}" ] || die "input does not look like a rootfs: missing /${required}"
done

log "Preparing chroot"
mkdir -p "${ROOTFS_DIR}"/{dev,dev/pts,proc,sys,run,tmp}
mount --bind /dev "${ROOTFS_DIR}/dev"
mount --bind /dev/pts "${ROOTFS_DIR}/dev/pts"
mount -t proc proc "${ROOTFS_DIR}/proc"
mount -t sysfs sysfs "${ROOTFS_DIR}/sys"
mount --bind /run "${ROOTFS_DIR}/run"

[ ! -e "${DNS_BACKUP}" ] && [ ! -L "${DNS_BACKUP}" ] \
    || die "temporary DNS backup path already exists in input rootfs"
if [ -e "${ROOTFS_DIR}/etc/resolv.conf" ] || [ -L "${ROOTFS_DIR}/etc/resolv.conf" ]; then
    mv "${ROOTFS_DIR}/etc/resolv.conf" "${DNS_BACKUP}"
fi
cp /etc/resolv.conf "${ROOTFS_DIR}/etc/resolv.conf"
cp /etc/resolv.conf "${DNS_INJECTED}"
DNS_PREPARED=1

log "Muting apt hooks that only cost time in a chroot"
disable_apt_hooks

case "${ACTION}" in
    overlay)
        log "Applying overlay stack: ${STACK}"
        python3 "${OVERLAY_ENGINE}" apply \
            --overlay-dirs "${OVERLAY_ROOT}" \
            --mount-point "${ROOTFS_DIR}" \
            --stack "${STACK}"
        ;;
    kernel)
        KERNEL_PACKAGE="$(dpkg-deb -f "${KERNEL_IMAGE_DEB}" Package)"
        KERNEL_VERSION="$(dpkg-deb -f "${KERNEL_IMAGE_DEB}" Version)"
        KERNEL_ARCH="$(dpkg-deb -f "${KERNEL_IMAGE_DEB}" Architecture)"
        log "Installing kernel: ${KERNEL_PACKAGE} ${KERNEL_VERSION} (${KERNEL_ARCH})"
        install -d -m 0755 "${ROOTFS_DIR}/tmp/tachyon-kernel"
        install -m 0644 "${KERNEL_IMAGE_DEB}" \
            "${ROOTFS_DIR}/tmp/tachyon-kernel/image.deb"
        install -m 0644 "${KERNEL_MODULES_DEB}" \
            "${ROOTFS_DIR}/tmp/tachyon-kernel/modules.deb"
        install -m 0644 "${KERNEL_HEADERS_DEB}" \
            "${ROOTFS_DIR}/tmp/tachyon-kernel/headers.deb"
        install -m 0644 "${KERNEL_COMMON_HEADERS_DEB}" \
            "${ROOTFS_DIR}/tmp/tachyon-kernel/common-headers.deb"
        install -m 0755 /usr/local/bin/install-kernel \
            "${ROOTFS_DIR}/tmp/tachyon-install-kernel"
        chroot "${ROOTFS_DIR}" /bin/bash \
            /tmp/tachyon-install-kernel \
            /tmp/tachyon-kernel/image.deb \
            /tmp/tachyon-kernel/modules.deb \
            /tmp/tachyon-kernel/headers.deb \
            /tmp/tachyon-kernel/common-headers.deb
        rm -f "${ROOTFS_DIR}/tmp/tachyon-install-kernel"
        rm -rf "${ROOTFS_DIR}/tmp/tachyon-kernel"
        ;;
esac

normalize_root_fstab

log "Closing chroot"
unmount_chroot
restore_dns
restore_apt_hooks

if [ "${ROOTFS_SIZE_MB}" = auto ]; then
    USED_KB="$(du -sk "${ROOTFS_DIR}" | awk '{print $1}')"
    ROOTFS_SIZE_MB=$(( USED_KB * 120 / 100 / 1024 + 256 ))
fi

OUTPUT_TMP="${OUTPUT_IMAGE}.tmp.$$"
rm -f "${OUTPUT_TMP}"
log "Creating output ext4: ${OUTPUT_IMAGE} (${ROOTFS_SIZE_MB} MiB)"
truncate -s "${ROOTFS_SIZE_MB}M" "${OUTPUT_TMP}"
MKFS_ARGS=(-q -F -b 4096 -L "${FS_LABEL}")
[ -n "${FS_UUID}" ] && MKFS_ARGS+=(-U "${FS_UUID}")
mkfs.ext4 "${MKFS_ARGS[@]}" -d "${ROOTFS_DIR}" "${OUTPUT_TMP}"
fsck_repair_gate "${OUTPUT_TMP}"
mv -f "${OUTPUT_TMP}" "${OUTPUT_IMAGE}"
OUTPUT_TMP=""

log "Done: ${OUTPUT_IMAGE}"
ls -lh "${OUTPUT_IMAGE}"
