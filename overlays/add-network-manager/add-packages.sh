#!/bin/bash
set -euo pipefail

# Assumes apt is already upgraded

# Will install the following core packages and dependencies
#   libnetplan0 python3-netifaces netplan.io
#   libbluetooth3 libmbim-glib4 libmbim-proxy libmm-glib0 libndp0 libnewt0.52
#   libnm0 libpcsclite1 libpolkit-agent-1-0 libpolkit-gobject-1-0 libqmi-glib5
#   libqmi-proxy libteamdctl0 modemmanager network-manager network-manager-pptp
#   policykit-1 ppp pptp-linux usb-modeswitch usb-modeswitch-data wpasupplicant
#   whiptail locales

# Add in minimal install packages for managing WiFi and networks as well as a default
# textual interface needed for setup
if apt-get install -y netplan.io network-manager whiptail locales; then
  echo "NetworkManager packages installed successfully."
else
  echo "Error installing NetworkManager packages."
  exit 1
fi
