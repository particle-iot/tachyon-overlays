#!/bin/bash
# Package the patched libgstpipewire.so.
#
# The plugin binary is prebuilt and lives in assets/. Rebuilding it needs an
# arm64 container and is a separate step - see build-plugin.sh - because it
# only has to happen when the upstream source or the patch changes, not on
# every package build.
set -euo pipefail
cd "$(dirname "$0")"

PKG=tachyon-gst-pipewire-camfix
VER=${VER:-1.0}
# Build output goes outside the source tree. The copy that actually ships is
# committed under overlays/<name>/files/; a second one next to the sources
# would let the two drift.
OUT=${1:-$(cd ../.. && pwd)/output/packages}
mkdir -p "$OUT"

SO=assets/libgstpipewire.so
[ -f "$SO" ] || { echo "$SO missing - run build-plugin.sh first" >&2; exit 1; }

# A plugin built for the wrong architecture would install cleanly and then
# simply not load, which looks like the patch not working.
file "$SO" | grep -q aarch64 || { echo "$SO is not aarch64" >&2; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

install -d -m 755 "$STAGE/DEBIAN" \
                  "$STAGE/usr/share/$PKG" \
                  "$STAGE/usr/share/doc/$PKG"

# Payload goes to a path we own; postinst copies it over the diverted one.
# Shipping it directly at the real path would collide with the diversion.
install -m 644 "$SO" "$STAGE/usr/share/$PKG/libgstpipewire.so"

install -m 755 src/postinst "$STAGE/DEBIAN/postinst"
install -m 755 src/prerm    "$STAGE/DEBIAN/prerm"
install -m 644 README.md    "$STAGE/usr/share/doc/$PKG/README.md"

cat > "$STAGE/DEBIAN/control" <<EOF
Package: $PKG
Version: $VER
Architecture: arm64
Maintainer: Tachyon camera <eugene@particle.io>
Depends: gstreamer1.0-pipewire (= 1.0.5-1ubuntu3.3)
Section: video
Priority: optional
Description: Patched PipeWire GStreamer source for the Tachyon camera
 Rebuilds libgstpipewire.so from PipeWire 1.0.5 with always-copy enabled by
 default, so pipewiresrc hands downstream its own copy of each frame instead
 of PipeWire's mapping.
 .
 Without it, stopping a recording in GNOME Snapshot faults inside
 gst_video_frame_copy - PipeWire withdraws a buffer while a downstream element
 is still reading through the mapping. Measured on this board: 18 crashes in
 20 attempts without, 0 in 20 with.
 .
 The upstream fix for the same defect is PipeWire commit bb1bb07f6, first
 released in 1.5.81. This package is the stop-gap until that reaches the
 archive, and should be dropped once it does.
 .
 Costs one full-frame copy per frame - about 3% of one core at 1920x1440.
EOF

deb="$OUT/${PKG}_${VER}_arm64.deb"
dpkg-deb --root-owner-group --build "$STAGE" "$deb" >/dev/null
echo "built: $deb"
