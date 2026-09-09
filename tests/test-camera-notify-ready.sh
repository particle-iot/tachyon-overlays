#!/bin/bash
# Offline regression test for the camera readiness notifier. The real failure
# happened only at boot, so keep the two important contracts executable:
# readiness means "one frame dequeued", and notification means remove then add.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
HELPER="$ROOT/packages/tachyon-camera-camx-qcm6490/src/tachyon-camera-notify-ready"
RULE="$ROOT/packages/tachyon-camera-camx-qcm6490/src/60-tachyon-camera.rules"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

cat >"$TMP/bin/timeout" <<'EOF'
#!/bin/bash
shift
exec "$@"
EOF

cat >"$TMP/bin/v4l2-ctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$CALL_LOG"
for arg in "$@"; do
    case "$arg" in
        --stream-to=*) stream_file=${arg#--stream-to=} ;;
    esac
done
if [[ "${V4L2_WRITE_FRAME:-1}" == 1 && -n "${stream_file:-}" ]]; then
    printf 'one captured frame\n' >"$stream_file"
fi
exit "${V4L2_RESULT:-0}"
EOF

cat >"$TMP/bin/udevadm" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == info ]]; then
    printf '/devices/virtual/mem/null\n'
else
    printf '%s\n' "$*" >>"$UDEV_LOG"
fi
EOF

cat >"$TMP/bin/sleep" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == 1 ]]; then
    /bin/sleep 1
fi
exit 0
EOF
chmod +x "$TMP/bin/"*

export CALL_LOG="$TMP/v4l2.log"
export UDEV_LOG="$TMP/udev.log"
TMPDIR="$TMP" PATH="$TMP/bin:$PATH" DEVICE=/dev/null READY_TIMEOUT_SEC=2 \
    REANNOUNCE_DELAY_SEC=0 bash "$HELPER" >"$TMP/stdout" 2>"$TMP/stderr"

grep -Fq -- '--stream-mmap=3 --stream-count=1 --stream-to=' "$CALL_LOG"
cat >"$TMP/expected-udev.log" <<'EOF'
trigger --action=remove /sys/devices/virtual/mem/null
settle --timeout=5
trigger --action=add /sys/devices/virtual/mem/null
settle --timeout=5
EOF
cmp "$TMP/expected-udev.log" "$UDEV_LOG"
grep -Fq 're-enumerated /dev/null' "$TMP/stdout"

# v4l2-ctl returns success for an OUTPUT-only v4l2loopback node even though it
# prints "unsupported stream type" and dequeues nothing.  A zero-byte probe
# must not emit the remove/add sequence or claim readiness.
: >"$UDEV_LOG"
V4L2_WRITE_FRAME=0 TMPDIR="$TMP" PATH="$TMP/bin:$PATH" DEVICE=/dev/null \
    READY_TIMEOUT_SEC=1 bash "$HELPER" \
    >"$TMP/false-success.stdout" 2>"$TMP/false-success.stderr"
[[ ! -s "$UDEV_LOG" ]]
grep -Fq 'allowing desktop startup without a camera' "$TMP/false-success.stderr"

# The timeout path must remain non-fatal and must not emit partial udev events;
# otherwise an absent camera could either block graphical boot or leave a
# working character device hidden from the rest of the system.
: >"$UDEV_LOG"
V4L2_RESULT=1 TMPDIR="$TMP" PATH="$TMP/bin:$PATH" DEVICE=/dev/null READY_TIMEOUT_SEC=0 \
    bash "$HELPER" >"$TMP/timeout.stdout" 2>"$TMP/timeout.stderr"
[[ ! -s "$UDEV_LOG" ]]
grep -Fq 'allowing desktop startup without a camera' "$TMP/timeout.stderr"

# Cold boot also depends on correcting the udev database value captured during
# v4l2loopback's original OUTPUT-only add event. Keep that card-label-scoped
# override from disappearing in a later cleanup.
grep -Fq 'ATTR{name}=="Tachyon CamX Bridge"' "$RULE"
grep -Fq 'ENV{ID_V4L_CAPABILITIES}=":capture:"' "$RULE"

echo 'camera notify-ready tests passed'
