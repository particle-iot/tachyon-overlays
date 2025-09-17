#!/bin/sh

LOG_FILE="/var/log/particle.log"
LED_PATH="/sys/class/leds/green/brightness"
RESIZE_DEVICE="/dev/disk/by-partlabel/system_a"

log_message() {
    echo "$1 at $(date)" >> "$LOG_FILE"

    #local to journal log
    echo "$1"
}

set_linux_running_led_brightness() {
    if [ -w "$LED_PATH" ]; then
        echo "$1" > "$LED_PATH"
    else
        log_message "Error: Unable to write to $LED_PATH"
    fi
}

init_gpio() {
    log_message "Initializing gpio"
    #call /usr/bin/gpio.sh init
    /usr/bin/gpio.sh init display_cam
    /usr/bin/gpio.sh init MCU
    /usr/bin/gpio.sh init 40pin
    /usr/bin/gpio.sh init power
}

set_activity_light() {
    log_message "Setting activity light"
    echo activity > /sys/class/leds/activity_led/trigger
}

init_touchscreen() {
    # If the DSI screen is used, the touch screen i2c device can fail to probe on boot due to the order of device initialization and the shared reset pin between them.
    I2C_NUMBER=$(ls /sys/devices/platform/soc/a94000.i2c/ | grep -o 'i2c-[0-9]\+' | sed 's/i2c-//')

    if [ ! -e /sys/bus/i2c/drivers/fts_ts/${I2C_NUMBER}-0038 ]; then
        log_message "Attempting to probe touch screen controller on DSI i2c bus ${I2C_NUMBER}"
        echo "${I2C_NUMBER}"-0038 > /sys/bus/i2c/drivers/fts_ts/bind
        if [[ $? -ne 0 ]]; then
            log_message "Error: Failed to probe touch screen controller."
        fi
    fi
}

update_hostname() {
    # Extract the SoC serial number from the device tree /sys/devices/soc0/serial_number
    RAW_SERIAL=$(cat /sys/devices/soc0/serial_number 2>/dev/null)
    if [ -z "$RAW_SERIAL" ]; then
        log_message "Error: Unable to read serial number from /sys/devices/soc0/serial_number."
        return 1
    fi
    # Converted to hex and padded to 8 chars
    SERIAL=$(printf "%08x" "${RAW_SERIAL}")


    # Define the new hostname
    MACHINE="tachyon-${SERIAL}"

    # Get the current hostname
    CURRENT_HOSTNAME=$(hostname)

    # Only proceed if the current hostname is 'qcs6490'
    if [[ "${CURRENT_HOSTNAME}" == *qcs6490* ]]; then
        log_message "Updating hostname to '${MACHINE}'."

        # Update /etc/hostname
        echo "${MACHINE}" > /etc/hostname

        # Update /etc/hosts
        echo -e "127.0.0.1 localhost\n127.0.1.1 ${MACHINE}" > /etc/hosts

        # Apply the new hostname
        hostnamectl set-hostname "${MACHINE}"

        log_message "Hostname updated to '${MACHINE}'."
    else
        log_message "Hostname is not 'qcs6490'. No changes made."
    fi
}

init_bluetooth() {
    state=$(systemctl is-active "bluetooth")
    if [ "$state" = "active" ]; then
        bluetoothctl system-alias Tachyon-${SERIAL}
        log_message "set bluetooth system alias"
    else
        log_message "bluetooth service not started, not setting system-alias"
    fi
}

case "$1" in
  pre)
    log_message "System is suspending"
    set_linux_running_led_brightness 0
    ;;
  post)
    log_message "System has resumed"
    set_linux_running_led_brightness 255
    ;;
  *)
    log_message "**********"
    log_message "** System is starting up"
    log_message "**********"
    update_hostname
    init_gpio
    set_activity_light
    init_touchscreen
    init_bluetooth
    ;;
esac

exit 0
