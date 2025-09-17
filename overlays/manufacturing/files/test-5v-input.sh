#!/bin/bash

# Check if USB type is DCP
USB_TYPE=$(cat /sys/class/power_supply/usb/type)
if [ "$USB_TYPE" != "USB_DCP" ]; then
    echo "Not DCP, got '$USB_TYPE'"
    echo "FAIL"
    exit 1
fi

# Check if voltage is exactly 5V (5000000 microvolts)
VOLTAGE_MAX=$(cat /sys/class/power_supply/usb/voltage_max)
if [ "$VOLTAGE_MAX" -ne 5000000 ]; then
    echo "Voltage is not 5V, got ${VOLTAGE_MAX}uV"
    echo "FAIL"
    exit 1
fi

# Check if current is exactly 3A (3000000 microamps)
CURRENT_MAX=$(cat /sys/class/power_supply/usb/current_max)
if [ "$CURRENT_MAX" -ne 3000000 ]; then
    echo "Current is not 3A, got ${CURRENT_MAX}uA"
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
