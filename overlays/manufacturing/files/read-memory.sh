#!/bin/bash
set -euo pipefail

# Print PASS on success or FAIL on error
trap 'rc=$?; if [ $rc -ne 0 ]; then echo "FAIL"; exit 1; else echo "PASS"; fi' EXIT

# Use /proc/meminfo for faster and more reliable memory detection
MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
if [ -z "$MEM_KB" ]; then
    echo "Error: Could not read memory information"
    exit 1
fi

# Direct comparison with 6GB threshold
if [ $MEM_KB -gt $((6 * 1024 * 1024)) ]; then # > 6GB, consider as 8GB
    echo "memory = 8"
    exit 0
else
    echo "memory = 4"
    exit 0
fi
