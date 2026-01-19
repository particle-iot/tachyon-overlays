#!/bin/sh
# Recover ADB gadget on Type-C role changes (Tachyon / dwc3-qcom).
# When switching from host to device mode, restart adbd to re-establish USB connection.

set -u
PATH=/usr/sbin:/usr/bin:/sbin:/bin

UDC="a600000.usb"
GADGET="/sys/kernel/config/usb_gadget/g1"
ACTION="${ACTION:-systemd}"

log() { logger -t adbd-role-switch "$*"; }

data_role="$(cat /sys/class/typec/port0/data_role 2>/dev/null || echo unknown)"
udc_now="$(cat "$GADGET/UDC" 2>/dev/null || echo none)"
log "START action=$ACTION data_role='$data_role' udc='$udc_now'"

# Only act when in device mode
echo "$data_role" | grep -q '\[device\]' || { log "SKIP not in device role"; exit 0; }

# Check adbd is enabled
systemctl is-enabled --quiet adbd.service || { log "SKIP adbd not enabled"; exit 0; }

# Wait for UDC to appear (may take a moment after role switch)
i=0
while [ ! -e "/sys/class/udc/$UDC" ] && [ $i -lt 20 ]; do
    log "WAIT for UDC ($i)"
    sleep 0.5
    i=$((i+1))
done

[ -e "/sys/class/udc/$UDC" ] || { log "ERROR UDC not available after wait"; exit 1; }

# Always restart adbd on role switch to device mode
# This ensures the USB gadget and endpoints are properly re-initialized
log "RESTART adbd for role switch recovery"
systemctl restart adbd || true

sleep 1
udc_end="$(cat "$GADGET/UDC" 2>/dev/null || echo none)"
log "END udc='$udc_end'"
exit 0
