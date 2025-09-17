#!/bin/bash
set -euo pipefail

# Print PASS on success or FAIL on error
trap 'rc=$?; if [ $rc -ne 0 ]; then echo "FAIL"; else echo "PASS"; fi' EXIT

# Exit if particle-tachyon-rild service is running
if systemctl is-active --quiet particle-tachyon-rild; then
    echo "Error: particle-tachyon-rild service is running. Please stop it before executing."
    exit 1
fi

 # Set log level to 2 to supress glink_pkt_ioctl messages
ORIGINAL_LEVEL=$(cat /proc/sys/kernel/printk | awk '{print $1}')
dmesg -n 2

EID=$(particle-tachyon-rild sim --fct | grep "EID:" | sed 's/.*EID: //')

# Restore original log level
dmesg -n "$ORIGINAL_LEVEL"

if [[ $EID =~ ^89[0-9]{30}$ ]]; then
    echo "eid = $EID"
    exit 0
else
    echo "Error: EID does not match expected format, got $EID"
    exit 1
fi
