#!/bin/bash
set -euo pipefail

echo "Setting up Qualcomm modem partitions..."

# Address /persist by partition label, not by /dev/sdXN. The kernel's scsi
# device letters follow the UFS LUN order, so a raw path bakes in one specific
# partition layout: /dev/sdf8 was LUN 5 partition 8, which is where the 20.04
# layout kept persist. 24.04 moved persist to LUN 0, so the raw path resolves
# to nothing and this script died on
#   mount: special device /dev/sdf8 does not exist
#   mke2fs: The file /dev/sdf8 does not exist and no size was specified
# taking particle-modem-setup down with it, and rmtfs/rild after that.
# by-partlabel is layout-independent and is already what the symlinks below use.
PERSIST=/dev/disk/by-partlabel/persist

if [ ! -e "${PERSIST}" ]; then
    echo "Error: ${PERSIST} does not exist; is the persist partition in the flashed layout?" >&2
    exit 1
fi

# Mount /persist partition if not already mounted
if ! mountpoint -q /persist; then
    echo "Mounting /persist partition..."
    if ! mount "${PERSIST}" /persist; then
        echo "Mount failed, formatting /persist partition with ext4..."
        mkfs.ext4 -F "${PERSIST}"
        echo "Retrying mount..."
        mount "${PERSIST}" /persist || echo "Warning: Failed to mount /persist after formatting"
    fi
fi

# Create the rmtfs directory and symlinks on the mounted /persist partition
mkdir -p /persist/rmtfs
cd /persist/rmtfs

ln -sf /dev/disk/by-partlabel/modemst1 modemst1
ln -sf /dev/disk/by-partlabel/modemst2 modemst2
ln -sf /dev/disk/by-partlabel/fsc fsc
ln -sf /dev/disk/by-partlabel/fsg fsg

echo "Modem partition setup completed successfully"
