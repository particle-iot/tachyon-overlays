#!/bin/bash

# Define device and mount point
DEVICE="/dev/nvme0n1p1"
MOUNT_POINT="/tmp/ssd"
SSD_FILE="$MOUNT_POINT/testfile.bin"
LOCAL_FILE="/tmp/local_testfile.bin"
SSD_CHECKSUM_FILE="/tmp/ssd_checksum.sha256"
LOCAL_CHECKSUM_FILE="/tmp/local_checksum.sha256"

FILE_SIZE_MB=64M

if [ ! -b "$DEVICE" ]; then
    echo "Device $DEVICE not found."
    echo "FAIL"
    exit 1
fi

# Create mount point directory if it doesn't exist
mkdir -p "$MOUNT_POINT"

# Mount the SSD if not already mounted
if ! mount | grep -q "$MOUNT_POINT"; then
    echo "Mounting $DEVICE to $MOUNT_POINT..."
    sudo mount "$DEVICE" "$MOUNT_POINT"
    if [ $? -ne 0 ]; then
        echo "Unable to mount $DEVICE"
        echo "FAIL"
        exit 1
    fi
fi

# Generate 64MB test files using the same data
# echo "Generating random data..."
dd if=/dev/urandom of="$LOCAL_FILE" bs=2M iflag=fullblock,count_bytes count=$FILE_SIZE_MB

echo "copy $LOCAL_FILE to $SSD_FILE"
rsync -aHAX --progress "$LOCAL_FILE" "$SSD_FILE"

# Calculate SHA256 checksums
# echo "comparing..."
diff $SSD_FILE $LOCAL_FILE
result=$?

# Clean up test files
rm -f "$SSD_FILE" "$LOCAL_FILE" "$SSD_CHECKSUM_FILE" "$LOCAL_CHECKSUM_FILE"

# Unmount /tmp/ssd
if umount /tmp/ssd; then
    echo "Unmount successful."
else
    echo "ERROR: Failed to unmount /tmp/ssd!" >&2
    echo "FAIL"
    exit 1
fi

# Compare
if [ "$result" -eq 0 ]; then
    echo "PASS"
    exit 0
else
    echo "FAIL"
    exit 1
fi
