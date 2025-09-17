#!/bin/bash
set -euo pipefail

# Print PASS on success or FAIL on error
trap 'rc=$?; if [ $rc -ne 0 ]; then echo "FAIL"; else echo "PASS"; fi' EXIT

DEVICE_ID_PREFIX=422a060000000000
SN=$(printf '%08x' $(< /sys/devices/soc0/serial_number))

if [[ "$SN" == "00000000" ]]; then
    echo "Error: formatted SN is all zeros"
    exit 1
fi

DEVICE_ID="${DEVICE_ID_PREFIX}${SN}"

if [ "${#DEVICE_ID}" -ne 24 ]; then
    echo "Error: unexpected device_id length ${#DEVICE_ID}, got '$DEVICE_ID', SN '$SN'"
    exit 1
fi

echo "device_id = $DEVICE_ID"
exit 0
