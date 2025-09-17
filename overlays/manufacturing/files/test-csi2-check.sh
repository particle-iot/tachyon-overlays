#!/bin/bash

# Camera ID, assume two cameras installed on both the CSI and DSI/CSI ports
camera_id=1

# Create a temporary file to store output
tmpfile=$(mktemp)

export XDG_RUNTIME_DIR=/run/user/root

cam_check(){
  # Kill this first
  fuser -k -9 /dev/video0
  sleep 2

  # Start the command in the background and capture its output
  gst-launch-1.0 qtiqmmfsrc camera=$camera_id name=qmmf 2>&1 | tee "$tmpfile" &

  # Get the PID of the background process
  pid=$!

  # Monitor output for 5 seconds or until the target text appears
  end_time=$((SECONDS + 10))
  while [ $SECONDS -lt $end_time ]; do
      if grep -q "New clock: GstSystemClock" "$tmpfile"; then
          kill "$pid" 2>/dev/null
          rm -f "$tmpfile"
          killall -9 gst-launch-1.0
          return 0
      fi

      if grep -q "Failed to Open Camera!" "$tmpfile"; then
          break # FAIL
      fi

      sleep 0.5
  done

  # If the 5 seconds expire without finding the text, terminate the process
  kill "$pid" 2>/dev/null
  rm -f "$tmpfile"
  return 1
}

echo "1st try..."
cam_check
if [ $? -eq 0 ]; then
  exit 0
fi

sleep 1

echo "2nd try..."
cam_check
if [ $? -eq 0 ]; then
  exit 0
else
  exit 1
fi
