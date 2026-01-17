#!/bin/sh
# Recover ADB gadget on Type-C role changes (Tachyon / dwc3-qcom).
# Important: do NOT call adbd-usb-gadget activate (it only rewrites UDC and can wedge EP0).

set -u
PATH=/usr/sbin:/usr/bin:/sbin:/bin

UDC="a600000.usb"
GADGET="/sys/kernel/config/usb_gadget/g1"
ACTION="${ACTION:-systemd}"

log() { logger -t adbd-role-switch "$*"; }

data_role="$(cat /sys/class/typec/port0/data_role 2>/dev/null || echo unknown)"
udc_now="$(cat "$GADGET/UDC" 2>/dev/null || echo none)"
log "START action=$ACTION data_role='$data_role' udc='$udc_now'"

echo "$data_role" | grep -q '\[device\]' || { log "SKIP not in device role"; exit 0; }

systemctl is-enabled --quiet adbd.service || { log "SKIP adbd not enabled"; exit 0; }
systemctl is-active  --quiet adbd.service || { log "SKIP adbd not active"; exit 0; }

# Ensure gadget exists (normally created by adbd.service)
if [ ! -d "$GADGET" ]; then
  log "SETUP gadget missing; restarting adbd to create it"
  systemctl restart adbd || true
fi

bounce_udc() {
  echo "" > "$GADGET/UDC" 2>/dev/null || true
  sleep 0.2
  i=0
  while [ $i -lt 10 ]; do
    if echo "$UDC" > "$GADGET/UDC" 2>/dev/null; then
      return 0
    fi
    i=$((i+1))
    sleep 0.2
  done
  return 1
}

reset_udc_driver() {
  DEV="$(readlink -f /sys/class/udc/$UDC/device)"
  DRIVER_DIR="$(readlink -f "$DEV/driver")"
  BASE="$(basename "$DEV")"
  log "RESET driver dev=$DEV driver=$DRIVER_DIR base=$BASE"

  systemctl stop adbd || true
  echo "$BASE" > "$DRIVER_DIR/unbind" 2>/dev/null || true
  sleep 1
  echo "$BASE" > "$DRIVER_DIR/bind" 2>/dev/null || true
  systemctl start adbd || true
}

log "TRY bounce_udc"
if bounce_udc; then
  log "OK bounce_udc; restarting adbd"
  systemctl restart adbd || true
  udc_end="$(cat "$GADGET/UDC" 2>/dev/null || echo none)"
  log "END success via bounce_udc udc='$udc_end'"
  exit 0
fi

log "WARN bounce_udc failed; escalating to driver reset"
reset_udc_driver
udc_end="$(cat "$GADGET/UDC" 2>/dev/null || echo none)"
log "END after driver reset udc='$udc_end'"
exit 0