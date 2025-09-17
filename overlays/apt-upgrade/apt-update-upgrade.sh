#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "Running apt update and upgrade..."

# Update the package lists
if apt-get update; then
  echo "Package lists updated successfully."
else
  echo "Error updating package lists."
  exit 1
fi

# Upgrade all packages
if apt-get upgrade -o Dpkg::Options::="--force-confold" -y; then
  echo "Packages upgraded successfully."
else
  echo "Error upgrading packages."
  exit 1
fi

#add nodejs to the list of ppa packages
curl -fsSL https://deb.nodesource.com/setup_22.x -o /tmp/nodesource_setup.sh
bash /tmp/nodesource_setup.sh

#add in basic packages nano, curl, wget, git, less, unzip, zip
if apt-get install -y nano curl wget git less unzip zip sudo device-tree-compiler input-utils gpiod minicom htop i2c-tools dstat nvme-cli usbutils apt-utils inotify-tools pciutils sl neofetch cmake nodejs avahi-daemon software-properties-common flatpak equivs iputils-ping; then
  echo "Basic packages installed successfully."
else
  echo "Error installing basic packages."
  exit 1
fi

#delete the minicom desktop file (if it exists)
if [ -e /usr/share/applications/minicom.desktop ]; then
  rm -f /usr/share/applications/minicom.desktop
fi


# Safely enable avahi-daemon
if [ ! -e /etc/systemd/system/multi-user.target.wants/avahi-daemon.service ]; then
  ln -s /lib/systemd/system/avahi-daemon.service /etc/systemd/system/multi-user.target.wants/avahi-daemon.service
else
  echo "avahi-daemon.service symlink already exists, skipping."
fi

echo "Apt update and upgrade completed successfully."
