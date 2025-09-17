#!/bin/bash

TARGET_KEYWORD="es8388-hp-jack"

# echo "Looking for device with keyword: $TARGET_KEYWORD"

# Find the line number of the device name that matches the target keyword
start_line=$(grep -n "N: Name=\".*$TARGET_KEYWORD.*\"" /proc/bus/input/devices | cut -d: -f1)

# If no matching device name found, exit with failure
if [ -z "$start_line" ]; then
    echo "Failed to find audio jack device."
    exit 1
fi

# From the start_line, search the next 10 lines for the Handlers line
handlers_line=$(sed -n "$start_line,$((start_line+10))p" /proc/bus/input/devices | grep "H: Handlers=")

# If no Handlers line found, exit with failure
if [ -z "$handlers_line" ]; then
    echo "Failed to find Handlers line."
    exit 1
fi

# Extract the event device (e.g., event5) from the Handlers line
event_dev=$(echo "$handlers_line" | grep -oE "event[0-9]+")

# If no event device found, exit with failure
if [ -z "$event_dev" ]; then
    echo "Failed to find event device."
    exit 1
fi

EVENT_PATH="/dev/input/$event_dev"

echo "Using device event: $EVENT_PATH"

# Run the audio-detect tool with a timeout of 5 seconds on the detected event device
timeout 5 /opt/particle/tests/audio-detect "$EVENT_PATH"
ret=$?

# Check the return status and print PASS or FAIL accordingly
if [ $ret -ne 0 ]; then
    echo "FAIL"
    exit 1
else
    echo "PASS"
    exit 0
fi
