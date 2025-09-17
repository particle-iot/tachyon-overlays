#!/bin/bash
if [ -e /sys/class/leds/activity_led/invert ]; then
	echo $1 > /sys/class/leds/activity_led/invert
fi
