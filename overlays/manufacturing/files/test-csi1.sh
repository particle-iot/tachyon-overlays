#!/bin/bash

camera_id=0

export XDG_RUNTIME_DIR=/run/user/root
if ! /opt/particle/tests/test-csi1-check.sh; then
    echo "FAIL"
    exit 1
fi

tmpfile=$(mktemp)
timeout 2 gst-launch-1.0 -e qtiqmmfsrc camera=$camera_id name=qmmf ! video/x-raw,format=NV12,width=640,height=480,framerate=30/1 ! jpegenc ! multifilesink location=$tmpfile

/opt/particle/tests/qr $tmpfile
result=$?

rm -f "$tmpfile"

if [ $result -eq 0 ]; then
    echo "PASS"
    exit 0
else
    echo "FAIL"
    exit 1
fi
