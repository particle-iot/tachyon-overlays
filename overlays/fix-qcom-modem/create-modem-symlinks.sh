#!/bin/bash
set -euo pipefail

# Create modem partition symlinks in /persist/rmts
cd /persist/rmts

ln -sf /dev/disk/by-partlabel/modemst1 modem_fs1
ln -sf /dev/disk/by-partlabel/modemst2 modem_fs2
ln -sf /dev/disk/by-partlabel/fsc       modem_fsc
ln -sf /dev/disk/by-partlabel/fsg       modem_fsg
ln -sf /dev/disk/by-partlabel/modemst1 modemfs1
ln -sf /dev/disk/by-partlabel/modemst2 modemfs2
ln -sf /dev/disk/by-partlabel/fsc       modemfsc
ln -sf /dev/disk/by-partlabel/fsg       modemfsg

echo "Modem partition symlinks created successfully"
