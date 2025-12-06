#!/bin/bash
set -euo pipefail

# Add fstab entries for Tachyon modem partitions (check for duplicates)
if ! grep -q '# Tachyon modem support' /etc/fstab; then
  cat >> /etc/fstab << 'EOF'

# Tachyon modem support
/dev/sdf8  /persist   ext4  rw,nosuid,nodev,noexec,noatime,discard,noauto_da_alloc,data=ordered  0  2
/dev/sdg1  /firmware  vfat  ro,nodev,noexec,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,errors=remount-ro  0  0
EOF
  echo "Tachyon modem fstab entries added"
else
  echo "Tachyon modem fstab entries already exist"
fi
