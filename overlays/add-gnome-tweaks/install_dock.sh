#!/bin/bash
set -euo pipefail

wget 'https://extensions.gnome.org/extension-data/dash-to-dockmicxgx.gmail.com.v69.shell-extension.zip' -O /tmp/ext.zip
mkdir -p /usr/share/gnome-shell/extensions/dash-to-dock@micxgx.gmail.com
unzip /tmp/ext.zip -d /usr/share/gnome-shell/extensions/dash-to-dock@micxgx.gmail.com
find /usr/share/gnome-shell/extensions/dash-to-dock@micxgx.gmail.com -type d -exec chmod 755 {} \;
find /usr/share/gnome-shell/extensions/dash-to-dock@micxgx.gmail.com -type f -exec chmod 644 {} \;
rm /tmp/ext.zip
