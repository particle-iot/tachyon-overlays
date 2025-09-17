#!/bin/bash

# Default threshold (seconds)
DEFAULT_THRESHOLD=20

# Log file to store the previous RTC value
RTC_LOG="/var/lib/rtc_time.log"

# Parse command-line arguments
if [ $# -gt 0 ]; then
    # Validate that argument is a positive integer
    if [[ "$1" =~ ^[0-9]+$ ]]; then
        THRESHOLD="$1"
    else
        echo "ERROR: Threshold must be a positive integer (seconds)" >&2
        echo "FAIL"
        exit 2
    fi
else
    THRESHOLD="$DEFAULT_THRESHOLD"
fi

# Check if the log file exists
if [ ! -f "$RTC_LOG" ]; then
    echo "No previous RTC log found!" >&2
    echo "FAIL"
    exit 1
fi

# Read RTC values
previous_rtc=$(cat "$RTC_LOG" 2>/dev/null)
current_rtc=$(cat /sys/class/rtc/rtc0/rtc_us_val 2>/dev/null)

# Validate RTC readings
if [ -z "$previous_rtc" ] || [ -z "$current_rtc" ]; then
    echo "ERROR: Failed to read RTC values!" >&2
    echo "FAIL"
    exit 3
fi

# Calculate time difference
time_diff=$((current_rtc - previous_rtc))
time_diff_sec=$((time_diff / 1000000))

# Display debug info (optional)
echo "Previous RTC (us): $previous_rtc"
echo "Current RTC (us): $current_rtc"
echo "Time difference (s): $time_diff_sec"
echo "Threshold (s): $THRESHOLD"

# Clean up log file
rm -f "$RTC_LOG"

# Evaluate against threshold
if [ "$time_diff_sec" -gt "$THRESHOLD" ]; then
    echo "Time difference > ${THRESHOLD}s"
    echo "PASS"
    exit 0
else
    echo "Time difference ≤ ${THRESHOLD}s"
    echo "FAIL"
    exit 1
fi
