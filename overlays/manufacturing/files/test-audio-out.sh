#!/bin/bash

default_tmpfile=/tmp/sound.wav
default_duration=10
ret=0

# Set log level to 1 to suppress glink_pkt_ioctl messages
ORIGINAL_LEVEL=$(cat /proc/sys/kernel/printk | awk '{print $1}')
sudo dmesg -n 1

# Parse optional duration argument
duration=$default_duration
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--duration)
            duration="$2"
            shift 2
            ;;
        -*|--*)
            echo "Unknown option $1"
            echo "FAIL"
            exit 1
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

# Restore positional parameters (in case filename is passed)
set -- "${POSITIONAL_ARGS[@]}"

# Set a play file path
tmpfile=${1:-$default_tmpfile}
user_specified_file=0
if [ $# -ge 1 ]; then
    user_specified_file=1
fi

set_mixer() {
    tinymix set 'PRIM_MI2S_RX Channels' 'Two'
    ret=$?
    if [ $ret -ne 0 ]; then
        return $ret
    fi

    tinymix set 'Output 1 Playback Volume' '32'
    ret=$?
    if [ $ret -ne 0 ]; then
        return $ret
    fi

    tinymix set 'PCM Volume' '192'
    ret=$?
    if [ $ret -ne 0 ]; then
        return $ret
    fi

    tinymix set 'Left Mixer Left Playback Switch' '1'
    ret=$?
    if [ $ret -ne 0 ]; then
        return $ret
    fi

    tinymix set 'Right Mixer Right Playback Switch' '1'
    ret=$?
    if [ $ret -ne 0 ]; then
        return $ret
    fi

    tinymix set 'OUT1_L Switch' '1'
    ret=$?
    if [ $ret -ne 0 ]; then
        return $ret
    fi

    tinymix set 'OUT1_R Switch' '1'
    ret=$?
    if [ $ret -ne 0 ]; then
        return $ret
    fi

    tinymix set 'PRI_MI2S_RX Audio Mixer MultiMedia1' '1'
    ret=$?
    if [ $ret -ne 0 ]; then
        return $ret
    fi
}

# Set Mixer
set_mixer
ret=$?
if [ $ret -ne 0 ]; then
    echo "FAIL"
    sudo dmesg -n "$ORIGINAL_LEVEL"
    exit $ret
fi

# check tmpfile
if [ ! -f "$tmpfile" ]; then
    echo "Error: File not found - $tmpfile"
    echo "FAIL"
    sudo dmesg -n "$ORIGINAL_LEVEL"
    exit 1
fi

# Play the audio file
if [ "$user_specified_file" -eq 1 ]; then
    timeout "${duration}s" tinyplay "$tmpfile" &
    play_pid=$!

    sleep 1
    if ps -p $play_pid > /dev/null; then
        wait $play_pid
        echo "PASS"
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
sudo dmesg -n "$ORIGINAL_LEVEL"
exit $ret
