#!/bin/bash

# Set log level to 1 to suppress glink_pkt_ioctl messages
ORIGINAL_LEVEL=$(cat /proc/sys/kernel/printk | awk '{print $1}')
dmesg -n 1

default_tmpfile="/tmp/sound.wav"
ret=0

tmpfile="${1:-$default_tmpfile}"
user_specified_file=0
if [ $# -ge 1 ]; then
    user_specified_file=1
fi

# Set mixer
tinymix set "DISPLAY_PORT1 Mixer MultiMedia1" "1"
ret=$?
if [ $ret -ne 0 ]; then
    echo "FAIL"
    dmesg -n "$ORIGINAL_LEVEL"
    exit $ret
fi

# check tmpfile
if [ ! -f "$tmpfile" ]; then
    echo "Error: File not found - $tmpfile"
    echo "FAIL"
    dmesg -n "$ORIGINAL_LEVEL"
    exit 1
fi

# Play the audio file
if [ "$user_specified_file" -eq 1 ]; then
    timeout 10s tinyplay "$tmpfile" &
    play_pid=$!

    sleep 1
    if ps -p $play_pid > /dev/null; then
        echo "PASS"
        wait $play_pid
        ret=0
    else
        echo "FAIL"
        ret=1
    fi
else
    tinyplay "$tmpfile"
    ret=$?
    if [ $ret -eq 0 ]; then
        echo "PASS"
    else
        echo "FAIL"
    fi
fi

# Restore original log level
dmesg -n "$ORIGINAL_LEVEL"
exit $ret
