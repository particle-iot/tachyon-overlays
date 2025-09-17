#!/bin/bash

# Define log file path (using /var/lib for persistence)
RTC_LOG="/var/lib/rtc_time.log"

# Read current RTC value and store it
current_rtc=$(cat /sys/class/rtc/rtc0/rtc_us_val)
echo "$current_rtc" > "$RTC_LOG"

sync "$RTC_LOG"

# Verify if the file was written successfully
if [ -f "$RTC_LOG" ]; then
    echo "RTC value: $current_rtc"
    echo "PASS"
    exit 0
else
    echo "Failed to save RTC value!" >&2
    echo "FAIL"
    exit 1
fi
