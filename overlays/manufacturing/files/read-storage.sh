#!/bin/bash
set -euo pipefail

# Print PASS on success or FAIL on error
trap 'rc=$?; if [ $rc -ne 0 ]; then echo "FAIL"; else echo "PASS"; fi' EXIT

SIZE_BYTES=$(lsblk -b -d -o SIZE /dev/sda | tail -n 1)
# Round to nearest 64 GB block and convert to GB.
# Ensure the disk size is a supported multiple of 64 GB.
STORAGE_GB=$(( (SIZE_BYTES + 34359738368) / 68719476736 * 64 ))

if [[ "$STORAGE_GB" == "64" || "$STORAGE_GB" == "128" ]]; then
    echo "storage = $STORAGE_GB"
    exit 0
else
    echo "Error: Storage size must be 64 or 128, got $STORAGE_GB GB"
    exit 1
fi
