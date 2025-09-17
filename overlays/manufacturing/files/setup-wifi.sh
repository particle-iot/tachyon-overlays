#!/bin/bash
set -euo pipefail

# Print PASS on success or FAIL on error
trap 'rc=$?; if [ $rc -ne 0 ]; then echo "FAIL"; else echo "PASS"; fi' EXIT

fail() {
  echo "WIFI SETUP ERROR: $1"
  exit 1
}

success() {
  echo "WIFI SETUP COMPLETE"
  exit 0
}

# Bring up the Wi-Fi stack

# Verify that ffbm.target is running
[ "$(systemctl is-active ffbm.target)" = "active" ] || fail "ffbm.target not active"

# If interface already exists, warn and succeed
if [ -d /sys/class/net/wlan0 ]; then
  echo "WIFI SETUP WARNING: wlan0 already exists"
  success
fi

# Load kernel module
insmod /lib/modules/5.4.219/extra/wlan.ko 2>/dev/null || fail "Kernel module insert failed"

# Wait up to 10s for interface to appear
for i in {1..10}; do
  [ -d /sys/class/net/wlan0 ] && break
  sleep 1
done

[ -d /sys/class/net/wlan0 ] || fail "wlan0 did not appear after insmod"

# Write wpa_supplicant config
cat <<EOF | tee /tmp/wpa_supplicant.conf > /dev/null
ctrl_interface=/run/wpa_supplicant
update_config=1
country=US
EOF

# Bring up the interface
ip link set wlan0 up || fail "Failed to bring up wlan0"

# Launch wpa_supplicant in background
wpa_supplicant -i wlan0 -c /tmp/wpa_supplicant.conf -D nl80211 -f /tmp/wpa.log &
WPA_PID=$!

sleep 2

ps -p $WPA_PID > /dev/null || fail "wpa_supplicant did not stay running"
iw dev wlan0 info | grep -q type || fail "wlan0 not ready"

success
