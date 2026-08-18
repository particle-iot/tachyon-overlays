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

# Ship the reasoning with the package. Whoever finds this installed on a board
# and wonders why an empty package is there should not have to find the repo to
# get an answer - the consequence of removing it is losing wifi.
install -d -m 755 pkg/usr/share/doc/tachyon-firmware-dragonwing-compat
install -m 644 README.md pkg/usr/share/doc/tachyon-firmware-dragonwing-compat/README.md

# dpkg-deb refuses group/other-writable dirs and wants root-owned content
find pkg -type d -exec chmod 755 {} +
find pkg -type f -exec chmod 644 {} +

dpkg-deb --root-owner-group --build pkg "$deb"
echo "built: $deb"
dpkg-deb -I "$deb" | sed -n '/Package:/,/^ /p'
