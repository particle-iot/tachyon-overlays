#!/bin/bash

EDID_PATH="/sys/class/drm/card0-DSI-1/edid"

# check EDID
if [ ! -f "$EDID_PATH" ]; then
    echo "FAIL"
    exit 1
fi

cat "$EDID_PATH" | parse-edid >/dev/null 2>&1
ret=$?
if [ "$ret" -ne 0 ]; then
    echo "FAIL"
    exit 1
fi

# Auto check webcam
detect_camera_device() {
    v4l2-ctl --list-devices | awk '
    BEGIN { found=0; dev="" }
    /Webcam/ { found=1; next }
    /^[ \t]*\/dev\/video[0-9]+/ && found {
        print $1
        found=0
    }' | head -n1
}

camdevice=$(detect_camera_device)

if [ $# -gt 0 ]; then
    if [[ $1 =~ ^[0-9]+$ ]]; then
        camdevice="/dev/video$1"
    else
        echo "Error: Argument must be a number (0,1,2...)"
        exit 1
    fi
fi

if [ ! -e "$camdevice" ]; then
    echo "FAIL: camera device $camdevice not found"
    exit 1
fi

tmpfile=$(mktemp)
ret=0

export XDG_RUNTIME_DIR=/run/user/root

# Kill the FCT screen
if pgrep -x "FCT" > /dev/null; then
    killall -9 FCT
fi
if pgrep -x "weston-image" > /dev/null; then
    echo "Image is already on LCD."
else
    weston-image /opt/particle/tests/tachyon.jpg &
    ret=$?
    if [ $ret -ne 0 ]; then
        echo "FAIL"
        exit 1
    fi
fi

v4l2-ctl --device=$camdevice --stream-mmap --stream-to=$tmpfile --stream-count=1
ret=$?
if [ $ret -ne 0 ]; then
    echo "FAIL"
    exit 1
fi

/opt/particle/tests/qr $tmpfile
ret=$?
if [ $ret -ne 0 ]; then
    echo "FAIL"
    exit 1
fi

echo "PASS"
exit $ret
