#!/bin/bash

# Base directory to store service state files
base_dir="/var/lib/systemd/state"

# List of services to check
services=(
  qcrild
  qcrild2
  qlrild
  particle-tachyon-rild
  particle-tachyon-gnss
  bluetooth
  hciattach
  ModemManager
  NetworkManager
)

log_service_state() {
    # Log state of services before suspending
    mkdir -p "$base_dir"

    for service in "${services[@]}"; do
        unit_name="${service}.service"

        # Check the active state of the service
        state=$(systemctl is-active "$unit_name")
        echo "Pre-suspend state: ${service}:${state}" | tee dev/kmsg

        echo "$state" > "${base_dir}/${service}"
    done
}

restart_services() {
    # restart only services that were running pre-suspend
    for service in "${services[@]}"; do
        unit_name="${service}.service"

        # Check the active state of the service
        state=$(cat "${base_dir}/${service}")
        echo "Post-suspend state: ${service}:${state}" | tee dev/kmsg

        if [ "$state" = "active" ]; then
            echo "Restarting $service" | tee dev/kmsg
            systemctl start $service
        fi
    done
}

case "$1" in
  pre)
    echo "Suspending services" | tee /dev/kmsg

    log_service_state

    for service in "${services[@]}"; do
        systemctl stop ${service}
    done

    # Delay until wifi powers off
    # TODO: Find a way to detect wifi hw powered off: nmcli state goes `unmanaged` as soon as suspend starts
    # state=$(nmcli -t -f DEVICE,STATE device | grep "^wlan0:" | cut -d: -f2)
    # echo "wlan0 nmcli state on sleep: $state." | tee /dev/kmsg
    sleep 10
    ;;
  post)
    echo "Resuming services" | tee /dev/kmsg

    restart_services
    ;;
esac
