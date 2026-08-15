#!/bin/bash
# Build tachyon-firmware-dragonwing-compat.
#
# Architecture: all - the package carries no binaries, only a Provides/Conflicts
# declaration and a note, so one artifact serves every board.
set -euo pipefail

cd "$(dirname "$0")"
OUT=${1:-.}

ver=$(awk '/^Version:/ {print $2}' pkg/DEBIAN/control)
deb="$OUT/tachyon-firmware-dragonwing-compat_${ver}_all.deb"

# dpkg-deb refuses group/other-writable dirs and wants root-owned content
find pkg -type d -exec chmod 755 {} +
find pkg -type f -exec chmod 644 {} +

dpkg-deb --root-owner-group --build pkg "$deb"
echo "built: $deb"
dpkg-deb -I "$deb" | sed -n '/Package:/,/^ /p'
