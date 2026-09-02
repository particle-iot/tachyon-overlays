#!/bin/bash
# Create the mountpoints the fstab needs, then regenerate the initramfs.
#
# There is one fstab. It used to be chosen at build time between a 1.1 layout
# and the new-BP 1.2+ one, keyed off ENV_UBUNTU_24_04_VERSION, but 1.1 has been
# retired -- the OS version and the BP version were the same number, so the
# variable only duplicated what the release version already said.
#
# Everything in the fstab resolves by label. Never reintroduce a /dev/sdXN: the
# kernel's SCSI letters follow UFS LUN order, so an index bakes in one specific
# partition table. Adding the misc partition to LUN 0 shifted system from sda3
# to sda4 and broke grub exactly that way, and the retired 1.1 fstab had been
# mounting /persist from a stale /dev/sdf8 for a whole layout generation --
# silently, because the entry carried `nofail`.
set -euo pipefail

mkdir -p /vendor /boot/dtb_a /persist

# 26.04/resolute's update-initramfs (dracut compat shim) rejects -t; try with it
# (24.04 initramfs-tools) then fall back without it.
update-initramfs -k all -t -u 2>/dev/null || update-initramfs -k all -u
