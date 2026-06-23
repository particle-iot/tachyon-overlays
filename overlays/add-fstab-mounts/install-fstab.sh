#!/bin/bash
# Select and install the correct fstab for the target Ubuntu 24.04 build.
#
# Build 1.1 (default / unset) uses the legacy layout with /boot/efi, bluetooth_a
# and a separate /firmware partition. Build 1.2+ ("new-BP") uses the cloud-image
# root label and the core_nhlos_a / dtb_a partitions, with no /boot/efi mount.
#
# Branches on PKG_UBUNTU_24_04_VERSION, which the overlay tool forwards into the
# chroot. The two candidate fstabs are staged at /tmp/fstab.11 and /tmp/fstab.12
# by the overlay's copy-into-chroot steps.
set -euo pipefail

VERSION="${PKG_UBUNTU_24_04_VERSION:-1.1}"

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
