#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="/var/log/particle.log"
DONE_FLAG="/var/lib/tachyon/growfs.done"
# Optional override via env; otherwise detected automatically
RESIZE_DEVICE_DEFAULT="/dev/disk/by-partlabel/system_a"

log() {
  # to file and journal/console
  echo "$1 at $(date)" | tee -a "$LOG_FILE"
}

if [ -f "$DONE_FLAG" ]; then
  log "growfs: already done; skipping"
  exit 0
fi

# Pick device: env -> detected root -> common fallbacks
DEV="${RESIZE_DEVICE:-}"
if [[ -z "${DEV}" ]]; then
  DEV="$(findmnt -no SOURCE / || true)"
fi
if [[ -z "${DEV}" || "${DEV}" == "/dev/root" ]]; then
  # fallback if findmnt shows /dev/root
  DEV="$(awk '$2=="/"{print $1}' /proc/mounts || true)"
fi
if [[ -z "${DEV}" || ! -b "${DEV}" ]]; then
  for cand in "${RESIZE_DEVICE_DEFAULT}" /dev/disk/by-label/cloudimg-rootfs; do
    if [[ -b "$cand" ]]; then DEV="$cand"; break; fi
  done
fi

if [[ -z "${DEV}" || ! -b "${DEV}" ]]; then
  log "growfs: ERROR: could not determine block device for rootfs"
  exit 1
fi

# Be a bit defensive: ensure it's ext4
FSTYPE="$(blkid -s TYPE -o value "${DEV}" || true)"
if [[ "${FSTYPE}" != "ext4" && -n "${FSTYPE}" ]]; then
  log "growfs: ${DEV} is type ${FSTYPE}; skipping (only ext4 is supported)"
  exit 0
fi

log "growfs: resizing ${DEV}..."
# Online resize is supported for ext4; root may be mounted rw already
if resize2fs "${DEV}" >> "${LOG_FILE}" 2>&1; then
  mkdir -p "$(dirname "${DONE_FLAG}")"
  echo "ok" > "${DONE_FLAG}"
  log "growfs: done"
else
  log "growfs: ERROR: resize2fs failed on ${DEV}"
  exit 1
fi