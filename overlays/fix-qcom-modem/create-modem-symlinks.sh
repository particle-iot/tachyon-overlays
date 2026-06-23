#!/bin/bash
set -euo pipefail

echo "Setting up Qualcomm modem partitions..."

# Mount /persist partition if not already mounted
if ! mountpoint -q /persist; then
    echo "Mounting /persist partition..."
    if ! mount /dev/sdf8 /persist; then
        echo "Mount failed, formatting /persist partition with ext4..."
        mkfs.ext4 -F /dev/sdf8
        echo "Retrying mount..."
        mount /dev/sdf8 /persist || echo "Warning: Failed to mount /persist after formatting"
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
