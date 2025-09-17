#!/bin/bash

EDID_PATH="/sys/class/drm/card0-DP-1/edid"

# Check if the edid file exists
if [ ! -f "$EDID_PATH" ]; then
    echo "FAIL"
    exit 1
fi

# Run parse-edid, discard output, only capture return code
cat "$EDID_PATH" | parse-edid >/dev/null 2>&1
ret=$?

if [ "$ret" -eq 0 ]; then
    echo "PASS"
else
    echo "FAIL"
fi

exit $ret
