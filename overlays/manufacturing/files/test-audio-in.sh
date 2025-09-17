#!/bin/bash

# Set log level to 2 to supress glink_pkt_ioctl messages
ORIGINAL_LEVEL=$(cat /proc/sys/kernel/printk | awk '{print $1}')
dmesg -n 1

duration=${1:-4}
tmpfile=${2:-/tmp/sound.wav}
ret=0

set_mixer() {
    tinymix set 'MultiMedia1 Mixer PRI_MI2S_TX' '1'
    ret=$?
    if [ $ret -ne 0 ]; then
        return $ret
    fi

    tinymix set 'Capture Digital Volume' '192'
    ret=$?
    if [ $ret -ne 0 ]; then
        return $ret
    fi

    tinymix set 'Left Channel Capture Volume' '8'
    ret=$?
    if [ $ret -ne 0 ]; then
        return $ret
    fi

    tinymix set 'Right Channel Capture Volume' '8'
    ret=$?
    if [ $ret -ne 0 ]; then
        return $ret
    fi

    tinymix set 'Capture Mute' '0'
    ret=$?
    if [ $ret -ne 0 ]; then
        return $ret
    fi

    tinymix set 'Left PGA Mux' 'Line 1L'
    ret=$?
    if [ $ret -ne 0 ]; then
        return $ret
    fi

    tinymix set 'ADC Source Mux' 'left data = left ADC, right data = left ADC'
    ret=$?
    if [ $ret -ne 0 ]; then
        return $ret
    fi

    return $ret
}

# Set Mixer
set_mixer
ret=$?
if [ $ret -ne 0 ]; then
    echo "FAIL"
    dmesg -n "$ORIGINAL_LEVEL"
    exit $ret
fi

# Capture audio from mic.
tinycap "$tmpfile" -t "$duration"
ret=$?
if [ $ret -eq 0 ]; then
  echo "PASS"
else
  echo "FAIL"
fi

# Restore original log level
dmesg -n "$ORIGINAL_LEVEL"
exit $ret
