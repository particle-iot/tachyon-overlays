#!/bin/bash
set -eo pipefail

# In chroot during build, we can't reliably detect the root filesystem label
# Just remove the LABEL= part and use device path instead for reliability
echo "Replacing LABEL=%ROOTFS_LABEL% with /dev/sda11 in /etc/fstab"

# Replace LABEL=%ROOTFS_LABEL% with /dev/sda11 (the actual root partition device)
if sed -i 's|LABEL=%ROOTFS_LABEL%|/dev/sda11|' /etc/fstab; then
  echo "Successfully updated fstab"
else
  echo "ERROR: sed command failed to update /etc/fstab" >&2
  exit 1
fi

# Verify the replacement happened
if grep -q '%ROOTFS_LABEL%' /etc/fstab; then
  echo "ERROR: %ROOTFS_LABEL% still present in fstab after replacement!" >&2
  echo "Current fstab contents:" >&2
  cat /etc/fstab >&2
  exit 1
fi

echo "fstab updated successfully - final contents:"
cat /etc/fstab
