#!/bin/bash
# Select and install the correct fstab for the target Ubuntu 24.04 build.
#
# Build 1.1 (legacy, opt-in via an explicit ENV_UBUNTU_24_04_VERSION=1.1) uses the
# legacy layout with /boot/efi, bluetooth_a and a separate /firmware partition.
# Build 1.2+ ("new-BP") -- the default when the variable is unset -- uses the
# cloud-image root label and the core_nhlos_a / dtb_a partitions, no /boot/efi.
#
# Branches on ENV_UBUNTU_24_04_VERSION, which the overlay tool forwards into the
# chroot. The two candidate fstabs are staged at /tmp/fstab.11 and /tmp/fstab.12
# by the overlay's copy-into-chroot steps.
#
# The default is new-BP. 1.1 no longer builds, and its fstab mounts /persist and
# /firmware by device node (/dev/sdf8, /dev/sdg1) rather than by label. Those
# indices shift whenever the partition table changes -- /persist is on LUN 0 in
# the current layout, not LUN 5 -- and both entries carry `nofail`, so a wrong
# index is a silent missing mount rather than a visible failure. Defaulting to a
# layout-dependent fstab that no longer matches the layout is the wrong way to
# fail, so an unset ENV_ now selects new-BP.
set -euo pipefail

# Print what we received so CI logs confirm the ENV_ value reached the chroot.
echo "[add-fstab-mounts] read ENV_UBUNTU_24_04_VERSION='${ENV_UBUNTU_24_04_VERSION:-}' (defaults to 1.2 if empty)"
VERSION="${ENV_UBUNTU_24_04_VERSION:-1.2}"

# True when VERSION >= 1.2 (dotted version compare via sort -V).
if [ "$(printf '%s\n1.2\n' "$VERSION" | sort -V | head -n1)" = "1.2" ]; then
    echo "[add-fstab-mounts] Ubuntu 24.04 build $VERSION -> new-BP fstab"
    mkdir -p /vendor /boot/dtb_a /persist
    install -m 644 /tmp/fstab.12 /etc/fstab
else
    echo "[add-fstab-mounts] Ubuntu 24.04 build $VERSION -> 1.1 fstab"
    mkdir -p /vendor /bt_firmware /boot/efi /persist /firmware
    install -m 644 /tmp/fstab.11 /etc/fstab
fi

# Clean up staged candidates.
rm -f /tmp/fstab.11 /tmp/fstab.12

update-initramfs -k all -t -u
