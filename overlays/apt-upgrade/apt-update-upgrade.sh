#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Every apt call below reaches the network, and a briefly unreachable or rate-limited
# mirror fails the step -- which loses a fully-fetched image build rather than producing
# a bad one. Seen on tachyon-composer PR #65: 36 fetches from ec2.ports.ubuntu.com came
# back 503 inside a single `apt-get upgrade` and took three of the four image jobs down.
# None of the affected packages were ours; the pinned Particle debs had already resolved.
#
# Measured on PR #65: the 503 burst that killed the build lasted 0.6s in one job and
# 4.1s in another. apt ships with no retries, so a sub-second blip costs a ~15 minute
# build. The failing transaction was all Ubuntu noble-updates packages -- libssl3t64,
# curl, krb5, linux-firmware, network-manager, systemd libs -- and contained none of
# our pinned Particle debs, which are not installed at this point and so cannot be in
# an `upgrade` transaction at all.
#
# Acquire::Retries makes apt retry an individual fetch, which alone covers a 0.6s blip;
# the loop covers apt giving up after that. Pipeline-Depth=0 serialises the fetch queue:
# one job emitted 35,650 "Tried to start delayed item ... but failed" warnings in those
# 4.1 seconds, which is apt's pipelined HTTP queue thrashing when a mirror errors
# mid-pipeline, and is what turns a hiccup into a hard failure. DPkg::Lock::Timeout is
# kept because the base image can have unattended-upgrades active while we work. Same shape as the apt_get helper the 20.04
# builder uses (tachyon-release-builder #213), without the sudo -- this already runs as
# root inside the chroot.
apt_get() {
  local attempt
  for attempt in 1 2 3 4 5; do
    if apt-get \
        -o DPkg::Lock::Timeout=600 \
        -o Acquire::Retries=3 \
        -o Acquire::http::Pipeline-Depth=0 \
        "$@"; then
      return 0
    fi
    echo "apt-get $* failed (attempt ${attempt}/5); retrying in 20s" >&2
    sleep 20
  done
  echo "apt-get $* still failing after 5 attempts" >&2
  return 1
}

echo "Running apt update and upgrade..."

# Update the package lists
if apt_get update; then
  echo "Package lists updated successfully."
else
  echo "Error updating package lists."
  exit 1
fi

# Upgrade all packages
if apt_get upgrade -o Dpkg::Options::="--force-confold" -y; then
  echo "Packages upgraded successfully."
else
  echo "Error upgrading packages."
  exit 1
fi

#add in basic packages nano, curl, wget, git, less, unzip, zip
if apt_get install -y nano xterm curl wget git less unzip zip sudo device-tree-compiler input-utils gpiod minicom htop i2c-tools dstat nvme-cli usbutils apt-utils inotify-tools pciutils sl neofetch cmake avahi-daemon software-properties-common flatpak equivs iputils-ping net-tools; then
  echo "Basic packages installed successfully."
else
  echo "Error installing basic packages."
  exit 1
fi


#add nodejs to the list of ppa packages
curl -fsSL --retry 5 --retry-all-errors --retry-delay 3 --connect-timeout 30 \
  https://deb.nodesource.com/setup_22.x -o /tmp/nodesource_setup.sh
bash /tmp/nodesource_setup.sh

# Install Node.js
if apt_get install -y nodejs; then
  echo "Node.js installed successfully."
else
  echo "Error installing Node.js."
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
