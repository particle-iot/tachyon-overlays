#!/bin/bash

DEVICE_NAME="fts_ts"

# Extract the event handler associated with the device
EVENT=$(awk -v name="$DEVICE_NAME" '
    BEGIN {found=0}
    /N: Name=/ {found=($0 ~ name)}
    found && /H: Handlers=/ {for (i=1; i<=NF; i++) if ($i ~ /^event[0-9]+$/) {print $i; exit}}
' /proc/bus/input/devices)

# Display the event device
if [[ -n "$EVENT" ]]; then
    echo "The event device for '$DEVICE_NAME' is: /dev/input/$EVENT"
else
    echo "Device '$DEVICE_NAME' not found."
fi

timeout 5 /opt/particle/tests/tp /dev/input/$EVENT
ret=$?
if [ $ret -ne 0 ]; then
    echo "FAIL"
    exit 1
else
    echo "PASS"
    exit 0
fi
