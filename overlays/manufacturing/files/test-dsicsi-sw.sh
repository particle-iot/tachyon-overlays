#!/bin/bash

camdevice=/dev/video0
tmpfile=$(mktemp)
ret=0

export XDG_RUNTIME_DIR=/run/user/root

# Load QR code first
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

# Set the switch to select camera instead of LCD.
gpio.sh init display_cam
if [ $ret -ne 0 ]; then
    echo "FAIL"
    exit $ret
fi

gpio.sh set 68 out 1
if [ $ret -ne 0 ]; then
    echo "FAIL"
    exit $ret
fi

# Capture an image, should not see any QR code now.
v4l2-ctl --device=$camdevice --stream-mmap --stream-to=$tmpfile --stream-count=1
ret=$?
if [ $ret -ne 0 ]; then
    echo "FAIL"
    exit 1
fi

/opt/particle/tests/qr $tmpfile
ret=$?
if [ $ret -ne 0 ]; then
    echo "PASS"
    exit 0
fi

echo "FAIL"
exit 1
