#!/bin/bash
# Load dconf settings for the particle user

set -e

export USER=particle
export HOME=/home/particle
export XDG_RUNTIME_DIR=/run/user/$(id -u particle)

mkdir -p /home/particle/.config/dconf
dconf load / < /etc/particle-desktop.dconf
chown -R particle:particle /home/particle/.config
