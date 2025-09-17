#!/bin/bash
set -euo pipefail

# Print PASS on success or FAIL on error
trap 'rc=$?; if [ $rc -ne 0 ]; then echo "FAIL"; else echo "PASS"; fi' EXIT

fail() {
  echo "WIFI TEARDOWN ERROR: $1"
  exit 1
}

success() {
  echo "WIFI TEARDOWN COMPLETE"
  exit 0
}

# Ensure we're in FCT mode
[ "$(systemctl is-active ffbm.target)" = "active" ] || fail "ffbm.target not active"

# Kill wpa_supplicant if running
pkill -f "wpa_supplicant.*wlan0" || echo "wpa_supplicant not running"

# Bring down the interface if it exists
if [ -d /sys/class/net/wlan0 ]; then
  ip link set wlan0 down || echo "Could not bring down wlan0"
  sleep 1
  # Remove the kernel module if loaded
  modprobe -r wlan || rmmod wlan || fail "Failed to remove wlan module"
fi

# Double check it's gone
[ ! -d /sys/class/net/wlan0 ] || fail "wlan0 still exists after teardown"

success
