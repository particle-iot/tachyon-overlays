#!/bin/bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
    echo "Usage: $0 'AT command'"
    exit 1
fi

AT_CMD="$1"
AT_CMD_LOWER=$(echo "$AT_CMD" | tr '[:upper:]' '[:lower:]')

# Exit if particle-tachyon-rild service is running
if systemctl is-active --quiet particle-tachyon-rild; then
    echo "Error: particle-tachyon-rild service is running. Please stop it before executing AT commands."
    exit 1
fi

# Execute the AT command using the Particle tool.
run_at() {
    ORIGINAL_LEVEL=$(awk '{print $1}' /proc/sys/kernel/printk)
    dmesg -n 2
    echo "$1" | particle-tachyon-rild
    dmesg -n "$ORIGINAL_LEVEL"
}

RESULT=$(run_at "$AT_CMD_LOWER")

if [[ "${DEBUG:-false}" == "true" ]]; then
    echo "[DEBUG] original command: $AT_CMD"
    echo "[DEBUG] lowercase command: $AT_CMD_LOWER"
    echo "[DEBUG] result: $RESULT"
fi

if [[ -z "$RESULT" ]]; then
    echo "Error: No response received when executing AT command '$AT_CMD'"
    exit 1
fi

# Check for any ERROR response (including +CME ERROR or +CMS ERROR)
if echo "$RESULT" | grep -q "ERROR"; then
    echo "Error: AT command '$AT_CMD_LOWER' returned an error response."
    echo "Output:"
    echo "$RESULT"
    exit 1
fi

echo "$RESULT"
