#!/bin/bash
# Build libgstpipewire.so for the board, inside an arm64 noble container.
#
# The board cannot reach the archive at any usable speed, so the headers come
# from a container here instead. It has to be a real arm64 container rather than
# a cross-toolchain: the plugin needs pipewire, spa and gstreamer development
# packages, and pulling the arm64 variants of all of those into an x86 sysroot
# is more work than letting qemu run apt.
#
# The one source change is DEFAULT_ALWAYS_COPY in gstpipewiresrc.c, already
# applied in the mounted tree.
#
# Versions matter: the .so is loaded next to the board's own libpipewire and
# gstreamer, so the build reports what it linked against and that has to match
# what is installed there (1.0.5-1ubuntu3.3 / gstreamer 1.24.2).
set -e
cd "$(dirname "$0")"

docker run --rm --network host --platform linux/arm64 \
    -v "$PWD/gstsrc:/src" \
    ubuntu:24.04 bash -c '
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
    gcc libc6-dev pkg-config \
    libpipewire-0.3-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
    >/dev/null

echo "=== versions in the build container ==="
dpkg-query -W -f="\${Package} \${Version}\n" libpipewire-0.3-dev libpipewire-0.3-0 \
    libgstreamer1.0-dev libgstreamer1.0-0 2>/dev/null

# The sources include each other as <gst/gstpipewirepool.h>, i.e. relative to
# the source root with src/gst/ still in the path, so the layout has to be
# recreated rather than compiled from a flat directory.
mkdir -p /build/gst
cp /src/*.c /src/*.h /build/gst/
# A stale config.h next to the sources would win over the one below, because a
# quoted include looks in its own directory first.
rm -f /build/gst/config.h

# HAVE_GSTREAMER_DEVICE_PROVIDER is what registers pipewiredeviceprovider, and
# that is how Snapshot finds the camera at all. Leaving it out would trade the
# crash for "no camera found" and tell us nothing.
# PACKAGE and PACKAGE_VERSION land in the plugin metadata via GST_PLUGIN_DEFINE.
# These values reproduce what the installed plugin already reports
# (Source module "pipewire", Version 1.0.5), so the rebuilt one is
# indistinguishable to anything that inspects the registry.
cat > /build/config.h <<EOF
#define PACKAGE "pipewire"
#define PACKAGE_VERSION "1.0.5"
#define HAVE_GSTREAMER_DEVICE_PROVIDER 1
EOF

PKGS="libpipewire-0.3 libspa-0.2 gstreamer-1.0 gstreamer-base-1.0 gstreamer-video-1.0 gstreamer-audio-1.0 gstreamer-allocators-1.0"

echo "=== compiling ==="
gcc -shared -fPIC -O2 -o /src/libgstpipewire.so \
    -I/build -I/build/gst $(pkg-config --cflags $PKGS) \
    /build/gst/gstpipewire.c /build/gst/gstpipewirecore.c /build/gst/gstpipewireclock.c \
    /build/gst/gstpipewireformat.c /build/gst/gstpipewirepool.c /build/gst/gstpipewiresink.c \
    /build/gst/gstpipewiresrc.c /build/gst/gstpipewiredeviceprovider.c \
    $(pkg-config --libs $PKGS)

echo "=== result ==="
ls -l /src/libgstpipewire.so
file /src/libgstpipewire.so 2>/dev/null || true
echo "=== undefined libs it needs ==="
objdump -p /src/libgstpipewire.so | grep NEEDED
'
