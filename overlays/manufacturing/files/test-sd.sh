#!/bin/bash

set -e
# === Config ===
MOUNT_POINT="/mnt/sdcard"
SD_FILE="$MOUNT_POINT/testfile.bin"
LOCAL_FILE="/tmp/local_testfile.bin"
SD_CHECKSUM="/tmp/sd_sha256.txt"
LOCAL_CHECKSUM="/tmp/local_sha256.txt"
FILE_SIZE_MB=10
NEED_UNMOUNT=false

mkdir -p "$MOUNT_POINT"

# Detect SD card device (supporting /dev/mmcblkXpY and /dev/mmcblkX)
MOUNTED_MMC=$(lsblk -rpno NAME,MOUNTPOINT | awk -v mp="$MOUNT_POINT" '$2 == mp && $1 ~ /\/dev\/mmcblk[0-9]+(p[0-9]+)?/ {print $1}' | head -n1)

if [ -n "$MOUNTED_MMC" ]; then
    DEVICE="$MOUNTED_MMC"
else
    DEVICE_CANDIDATES=($(lsblk -rpno NAME,TYPE,MOUNTPOINT | awk '$2=="part" && $3=="" && $1 ~ /\/dev\/mmcblk[0-9]+p[0-9]+/ {print $1}'))

    if [ ${#DEVICE_CANDIDATES[@]} -eq 0 ]; then
        DEVICE_CANDIDATES=($(lsblk -rpno NAME,TYPE,MOUNTPOINT | awk '$2=="disk" && $3=="" && $1 ~ /\/dev\/mmcblk[0-9]+/ {print $1}'))
    fi

    if [ ${#DEVICE_CANDIDATES[@]} -eq 0 ]; then
        echo "No SD card device found."
        echo "FAIL"
        exit 1
    elif [ ${#DEVICE_CANDIDATES[@]} -gt 1 ]; then
        echo "Multiple SD card candidates detected:"
        printf "  %s\n" "${DEVICE_CANDIDATES[@]}"
        echo "FAIL"
        exit 1
    else
        DEVICE="${DEVICE_CANDIDATES[0]}"
        mount "$DEVICE" "$MOUNT_POINT"
        NEED_UNMOUNT=true
    fi
fi

# Write test data (bypassing cache)
dd if=/dev/urandom of="$LOCAL_FILE" bs=1M count=$FILE_SIZE_MB oflag=direct status=none
dd if="$LOCAL_FILE" of="$SD_FILE" bs=1M oflag=direct status=none
sync

# Verify written data
sha256sum "$SD_FILE" > "$SD_CHECKSUM"
sha256sum "$LOCAL_FILE" > "$LOCAL_CHECKSUM"

SD_HASH=$(cut -d ' ' -f1 "$SD_CHECKSUM")
LOCAL_HASH=$(cut -d ' ' -f1 "$LOCAL_CHECKSUM")

# Clean up
rm -f "$SD_FILE" "$LOCAL_FILE" "$SD_CHECKSUM" "$LOCAL_CHECKSUM"

# Unmount if needed
if $NEED_UNMOUNT; then
    umount "$MOUNT_POINT"
fi

# Result
if [ "$SD_HASH" == "$LOCAL_HASH" ]; then
    echo "PASS"
    exit 0
else
    echo "FAIL"
    exit 1
fi
