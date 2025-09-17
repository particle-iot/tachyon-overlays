#!/bin/bash

# Check if USB type is USB-PD
USB_TYPE=$(cat /sys/class/power_supply/usb/type)
if [ "$USB_TYPE" != "USB_PD" ]; then
    echo "Not USB-PD, got '$USB_TYPE'"
    echo "FAIL"
    exit 1
fi

# Check if voltage is at least 9V (9000000 microvolts)
VOLTAGE_MAX=$(cat /sys/class/power_supply/usb/voltage_max)
if [ "$VOLTAGE_MAX" -lt 9000000 ]; then
    echo "Voltage less than 9V, got ${VOLTAGE_MAX}uV"
    echo "FAIL"
    exit 1
fi

# Check if current is greater than 1.5A (1500000 microamps)
CURRENT_MAX=$(cat /sys/class/power_supply/usb/current_max)
if [ "$CURRENT_MAX" -le 1500000 ]; then
    echo "Current not greater than 1.5A, got ${CURRENT_MAX}uA"
    echo "FAIL"
    exit 1
fi

# Check if battery is charging
BATTERY_STATUS=$(cat /sys/class/power_supply/battery/status)
if [ "$BATTERY_STATUS" != "Charging" ]; then
    echo "Battery is not charging, status is '$BATTERY_STATUS'"
    echo "FAIL"
    exit 1
fi

echo "$USB_TYPE"
echo "$VOLTAGE_MAX uV"
echo "$CURRENT_MAX uA"
echo "$BATTERY_STATUS"

echo "PASS"
exit 0
