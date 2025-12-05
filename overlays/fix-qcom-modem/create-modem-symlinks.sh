#!/bin/bash
set -euo pipefail

# Create modem partition symlinks in /persist/rmts
cd /persist/rmts

ln -sf /dev/disk/by-partlabel/modemst1 modemst1
ln -sf /dev/disk/by-partlabel/modemst2 modemst2
ln -sf /dev/disk/by-partlabel/fsc fsc
ln -sf /dev/disk/by-partlabel/fsg fsg

echo "Modem partition symlinks created successfully"
