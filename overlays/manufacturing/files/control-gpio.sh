#!/bin/bash

# control_gpio [gpio number] [out|in] [value if output: 0, 1]
# Exported number = GPIO_BASE + INPUT_GPIO_NUMBER
GPIO_BASE=336  # Offset value
GPIO_NUMBER=$1
DIRECTION=$2
GPIO_VALUE=$3

# Check if GPIO_NUMBER is empty
if [ -z "${GPIO_NUMBER}" ]; then
    echo "Error: GPIO number is required!"
    exit 1
fi

# Calculate actual GPIO number
GPIO_NUMBER=$(($GPIO_NUMBER + $GPIO_BASE))

# Check if the GPIO is already exported
if [ ! -d /sys/class/gpio/gpio$GPIO_NUMBER ]; then
    echo $GPIO_NUMBER > /sys/class/gpio/export
    if [ $? -ne 0 ]; then
        echo "Error: Failed to export GPIO $GPIO_NUMBER."
        exit 1
    fi
fi

# Set the GPIO direction
echo $DIRECTION > /sys/class/gpio/gpio$GPIO_NUMBER/direction
if [ $? -ne 0 ]; then
    echo "Error: Failed to set GPIO direction."
    exit 1
fi

# If the direction is output, set the value
if [[ $DIRECTION == "out" ]]; then
    echo $GPIO_VALUE > /sys/class/gpio/gpio$GPIO_NUMBER/value
    if [ $? -ne 0 ]; then
        echo "Error: Failed to set GPIO value."
        exit 1
    fi
fi

echo "GPIO $GPIO_NUMBER is configured as $DIRECTION with value $GPIO_VALUE (if output)."
