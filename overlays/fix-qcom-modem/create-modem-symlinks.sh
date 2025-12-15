#!/bin/bash
set -euo pipefail

echo "Setting up Qualcomm modem partitions..."

# Mount /persist partition if not already mounted
if ! mountpoint -q /persist; then
    echo "Mounting /persist partition..."
    mount /dev/sdf8 /persist || echo "Warning: Failed to mount /persist"
fi

# Mount /firmware partition if not already mounted
if ! mountpoint -q /firmware; then
    echo "Mounting /firmware partition..."
    mount /dev/sdg1 /firmware || echo "Warning: Failed to mount /firmware"
fi

# Create the rmtfs directory and symlinks on the mounted /persist partition
mkdir -p /persist/rmtfs
cd /persist/rmtfs

ln -sf /dev/disk/by-partlabel/modemst1 modemst1
ln -sf /dev/disk/by-partlabel/modemst2 modemst2
ln -sf /dev/disk/by-partlabel/fsc fsc
ln -sf /dev/disk/by-partlabel/fsg fsg

echo "Modem partition setup completed successfully"
