#!/bin/bash
# Install the patched PipeWire GStreamer source.
#
# Stopping a recording in GNOME Snapshot faults inside gst_video_frame_copy:
# pipewiresrc hands downstream PipeWire's own mapping rather than a copy, and
# PipeWire withdraws the buffer while a downstream element is still reading
# through it. Measured on this board: 18 crashes in 20 attempts without the
# patch, 0 in 20 with it.
#
# The package replaces libgstpipewire.so through dpkg-divert, so it is pinned
# to the exact gstreamer1.0-pipewire version it was built from - a plugin
# against a different ABI would load into a mismatched libpipewire.
set -euo pipefail

DEB=$(echo /tmp/tachyon-camfix/tachyon-gst-pipewire-camfix_*_arm64.deb)

die() { echo "FATAL: $*" >&2; exit 1; }

echo "### preflight"
[ -f "$DEB" ] || die "package not found: $DEB"

# apt would resolve the version dependency by trying to change
# gstreamer1.0-pipewire, which on this image means pulling a different
# PipeWire. Say so here rather than let that happen quietly.
want=$(dpkg-deb -f "$DEB" Depends | sed -n 's/.*gstreamer1\.0-pipewire (= \([^)]*\)).*/\1/p')
have=$(dpkg-query -W -f='${Version}' gstreamer1.0-pipewire 2>/dev/null || true)
[ -n "$have" ] || die "gstreamer1.0-pipewire is not installed; nothing to patch"
[ "$want" = "$have" ] \
    || die "plugin was built against gstreamer1.0-pipewire $want, image has $have"

echo "### install"
# Retries: a transient 503 from the archive should not end the image build.
apt-get install -y -o Acquire::Retries=3 "$DEB"

echo "### verify"
PLUGIN=/usr/lib/aarch64-linux-gnu/gstreamer-1.0/libgstpipewire.so
# The diversion is the mechanism: without it the next gstreamer1.0-pipewire
# upgrade silently restores the stock plugin and the crash returns with nothing
# to show why.
dpkg-divert --list | grep -q "$PLUGIN" || die "diversion for $PLUGIN missing"
[ -f "$PLUGIN.distrib" ] || die "the distribution's plugin was not moved aside"

# Confirm the file in place is ours and not the stock one restored behind us.
cmp -s /usr/share/tachyon-gst-pipewire-camfix/libgstpipewire.so "$PLUGIN" \
    || die "$PLUGIN is not the patched plugin"

echo "### patched pipewiresrc installed (always-copy on by default)"
