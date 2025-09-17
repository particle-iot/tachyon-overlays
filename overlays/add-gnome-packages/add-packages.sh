#!/bin/bash
set -euo pipefail

if apt update; then
  echo "apt update success"
else
  echo "Error runing apt update"
  exit 1
fi

# Upgrade installed packages
if apt-get upgrade -y; then
  echo "System upgrade completed successfully."
else
  echo "Error during system upgrade."
  exit 1
fi

# bluez5 package includes its own `/usr/bin/dbus-lanch` binary for unknown reasons, divert it to avoid package conflicts
if dpkg-divert --package dbus-x11 --divert /usr/bin/dbus-launch.bluez --rename /usr/bin/dbus-launch; then
  echo "Diverted bluez dbus-launch binary."
else
  echo "Failed to divert bluez dbus-launch."
  exit 1
fi

# echo "apt show bluez5"
# apt show bluez5

if apt-get install -y dpkg update-alternatives dialog gdm3 gnome-session-wayland pinentry-gnome3 gnome-terminal ; then
  echo "GNOME packages installed successfully."
else
  echo "Error installing GNOME packages."
  exit 1
fi

#add extra gnome apps

if apt-get install -y gnome-weather gnome-clocks gnome-calculator drawing gnome-maps gnome-mines gnome-system-monitor ; then
  echo "GNOME packages installed successfully."
else
  echo "Error installing GNOME packages."
  exit 1
fi

# make sure the update apps are uninstalled

if apt-get remove -y ubuntu-advantage-tools ; then
  echo "GNOME tools removed successfully."
else
  echo "Error removing GNOME tools."
  exit 1
fi

rm /var/cache/apt/archives/*.deb || exit 1
 