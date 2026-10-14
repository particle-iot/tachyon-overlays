#!/bin/bash
# Build tachyon-camera-camx-qcm6490.
#
# The symlinks under /usr/lib are created here, into the package payload, so
# dpkg owns them and handles install / upgrade / removal. Creating them from
# postinst instead would leave them outside dpkg's file database.
#
# preinst is generated from src/preinst.in with the manifest inlined: it has to
# guard those paths before unpack, at which point the manifest file itself is
# not yet on disk.
set -euo pipefail

cd "$(dirname "$0")"
# Build output goes outside the source tree. The copy that actually ships is
# committed under overlays/<name>/files/; a second one next to the sources
# would let the two drift.
OUT=${1:-$(cd ../.. && pwd)/output/packages}
mkdir -p "$OUT"
STAGE=$(mktemp -d)
# Scratch space kept OUTSIDE $STAGE - anything dropped in there lands in the
# package payload.
SCRATCH=$(mktemp -d)
trap 'rm -rf "$STAGE" "$SCRATCH"' EXIT

MANIFEST=manifest/usr-lib-symlinks.txt
[ -f "$MANIFEST" ] || { echo "missing $MANIFEST (run gen-symlink-manifest.sh)" >&2; exit 1; }

# ---- payload ----------------------------------------------------------
mkdir -p "$STAGE/DEBIAN" "$STAGE/usr/lib" "$STAGE/usr/share/tachyon-camera"
cp pkg/DEBIAN/control "$STAGE/DEBIAN/"
# Config under /etc that the operator is expected to edit. Without this list
# dpkg treats them as ordinary payload and silently overwrites local changes
# on every upgrade.
cp pkg/DEBIAN/conffiles "$STAGE/DEBIAN/"

# per-SoC layout: CamX hardcodes /usr/lib/hw and /usr/lib/camera
ln -sfn qcm6490/hw     "$STAGE/usr/lib/hw"
ln -sfn qcm6490/camera "$STAGE/usr/lib/camera"

n=0
while read -r link target; do
    case "$link" in ''|\#*) continue ;; esac
    mkdir -p "$STAGE$(dirname "$link")"
    ln -sfn "$target" "$STAGE$link"
    n=$((n + 1))
done < "$MANIFEST"
echo "staged $n /usr/lib symlinks"

cp "$MANIFEST" "$STAGE/usr/share/tachyon-camera/usr-lib-symlinks.txt"
install -d -m 755 "$STAGE/usr/share/doc/tachyon-camera-camx-qcm6490"
install -m 644 src/README.md "$STAGE/usr/share/doc/tachyon-camera-camx-qcm6490/README.md"
# Ship the provenance record with the package: where the vendor binaries came
# from and what was done to them should travel with the thing being installed,
# not stay behind in the build tree.
install -m 644 PROVENANCE.md "$STAGE/usr/share/doc/tachyon-camera-camx-qcm6490/PROVENANCE.md"

# Every artifact is mandatory. Silently emitting a same-named "layout-only"
# package when an asset is missing is how a broken image ships unnoticed.
REQUIRED_CAMERA="com.qti.sensormodule.tachyon_imx519_csi1_4lane.bin
com.qti.sensormodule.tachyon_imx519_csi2_4lane.bin
com.qti.sensorsocmap.socid_map.bin
com.qti.sensor.imx519.so
com.qti.tuned.sunny_imx519.bin"
REQUIRED_DTBO="combined-dtb-vendor-camera-imx519-csi1-4lane.dtbo
combined-dtb-vendor-camera-imx519-csi2-4lane.dtbo"
REQUIRED_TOOLS="camx-enum camx-capture camx-v4l2-bridge"
REQUIRED_GST="libgsttachyoncam.so"

for f in $REQUIRED_CAMERA; do
    [ -f "assets/camera/$f" ] || { echo "missing asset: assets/camera/$f" >&2; exit 1; }
done
for f in $REQUIRED_TOOLS; do
    [ -f "assets/tools/$f" ] || { echo "missing tool: assets/tools/$f" >&2; exit 1; }
done
for f in $REQUIRED_DTBO; do
    [ -f "assets/dtbo/$f" ] || { echo "missing dtbo: assets/dtbo/$f" >&2; exit 1; }
done
for f in $REQUIRED_GST; do
    [ -f "assets/gst/$f" ] || { echo "missing gst plugin: assets/gst/$f" >&2; exit 1; }
done

# Validate the sensor plugin positively: a truncated file, an x86 build, or
# anything readelf cannot parse must stop the build here.
PLUGIN=assets/camera/com.qti.sensor.imx519.so

# readelf exits 0 on a truncated file while complaining on stderr, so treat
# any diagnostic as fatal rather than trusting the exit status alone.
hdr=$(readelf -h "$PLUGIN" 2>"$SCRATCH/readelf.err") || { echo "$PLUGIN: not a readable ELF" >&2; exit 1; }
if [ -s "$SCRATCH/readelf.err" ]; then
    sed 's/^/  /' "$SCRATCH/readelf.err" >&2
    echo "$PLUGIN: malformed ELF" >&2
    exit 1
fi
case "$hdr" in
    *"DYN (Shared object file)"*) ;;
    *) echo "$PLUGIN: not a shared object" >&2; exit 1 ;;
esac
case "$hdr" in
    *AArch64*) ;;
    *) echo "$PLUGIN: not an AArch64 object" >&2; exit 1 ;;
esac

# CamX resolves exactly this entry point out of the plugin; without it the
# camera still runs, but on the generic gain math.
dyn=$(readelf -dW "$PLUGIN") || { echo "$PLUGIN: cannot read .dynamic" >&2; exit 1; }
# The old Ubuntu 20.04 prebuilt has no such soname; it reads the register
# addresses at the wrong offsets, so refuse it if it comes back.
case "$dyn" in
    *"[com.qti.sensor.imx519.so.0]"*) ;;
    *) echo "$PLUGIN: not built by build-assets.sh (soname)" >&2; exit 1 ;;
esac
syms=$(readelf -sW --dyn-syms "$PLUGIN") || { echo "$PLUGIN: cannot read .dynsym" >&2; exit 1; }
case "$syms" in
    *GetSensorLibraryAPIs*) ;;
    *) echo "$PLUGIN: does not export GetSensorLibraryAPIs" >&2; exit 1 ;;
esac

install -d -m 755 "$STAGE/usr/lib/qcm6490/camera"
install -m 644 assets/camera/* "$STAGE/usr/lib/qcm6490/camera/"
# CamX looks the plugin up as /usr/lib/camera/*.sensor.<name>.so.0 and, if
# that name is missing, silently falls back to generic gain math that is wrong
# for this sensor - which made auto-exposure hunt and the picture flicker.
ln -sf com.qti.sensor.imx519.so "$STAGE/usr/lib/qcm6490/camera/com.qti.sensor.imx519.so.0"
install -d -m 755 "$STAGE/usr/share/tachyon/dtbo"
install -m 644 assets/dtbo/* "$STAGE/usr/share/tachyon/dtbo/"
install -d -m 755 "$STAGE/usr/bin"
install -m 755 assets/tools/* "$STAGE/usr/bin/"
# vp8enc tuning for Snapshot/Cheese recordings, loaded by the environment.d entry.
install -d -m 755 "$STAGE/usr/lib/aarch64-linux-gnu/gstreamer-1.0"
install -m 644 assets/gst/libgsttachyoncam.so "$STAGE/usr/lib/aarch64-linux-gnu/gstreamer-1.0/"
install -d -m 755 "$STAGE/usr/lib/environment.d"
install -m 644 src/90-tachyon-camera.conf "$STAGE/usr/lib/environment.d/90-tachyon-camera.conf"
echo "staged $(ls -1 assets/camera | wc -l) camera assets, $(ls -1 assets/tools | wc -l) tools, $(ls -1 assets/dtbo | wc -l) dtbo"

# /var/cache/camera via tmpfiles, not by relying on CamX's first root run
install -d -m 755 "$STAGE/usr/lib/tmpfiles.d"
install -m 644 src/tachyon-camera.tmpfiles "$STAGE/usr/lib/tmpfiles.d/tachyon-camera.conf"

# ---- V4L2 bridge integration -------------------------------------------
# The bridge binary itself came in with assets/tools above. What follows is
# everything needed to run it as a service. postinst enables the unit on first
# install (including an image chroot) so desktop camera applications work on
# first boot. An operator can disable it later to free the exclusive HAL3
# camera for camx-capture; upgrades deliberately preserve that choice.
install -d -m 755 "$STAGE/usr/libexec"
install -m 755 src/tachyon-camera-bridge-start "$STAGE/usr/libexec/tachyon-camera-bridge-start"
# Waits for a dequeuable frame, then gives desktop consumers a remove/add pair.
# A plain udev change updates properties but does not make an already-running
# WirePlumber reconsider a V4L node rejected while it was OUTPUT-only.
install -m 755 src/tachyon-camera-notify-ready "$STAGE/usr/libexec/tachyon-camera-notify-ready"
install -m 755 src/tachyon-camera-tuning-patch "$STAGE/usr/libexec/tachyon-camera-tuning-patch"
install -d -m 755 "$STAGE/lib/systemd/system"
install -m 644 src/tachyon-camera-bridge.service "$STAGE/lib/systemd/system/tachyon-camera-bridge.service"
# Restarts the bridge cleanly across suspend.
install -d -m 755 "$STAGE/lib/systemd/system-sleep"
install -m 755 src/tachyon-camera-sleep "$STAGE/lib/systemd/system-sleep/tachyon-camera"
install -d -m 755 "$STAGE/etc/default"
install -m 644 src/tachyon-camera-bridge.default "$STAGE/etc/default/tachyon-camera-bridge"
install -d -m 755 "$STAGE/etc/modprobe.d"
install -m 644 src/tachyon-v4l2loopback.conf "$STAGE/etc/modprobe.d/tachyon-v4l2loopback.conf"
install -d -m 755 "$STAGE/lib/udev/rules.d"
install -m 644 src/60-tachyon-camera.rules "$STAGE/lib/udev/rules.d/60-tachyon-camera.rules"

# CamX settings. Conffile: the operator turns logging back on here when
# chasing an image-quality problem, and an upgrade must not undo that.
install -d -m 755 "$STAGE/var/cache/camera"
install -m 644 src/camxoverridesettings.txt "$STAGE/var/cache/camera/camxoverridesettings.txt"

# Bounds what the camera's log volume costs in flash. Conffile for the same
# reason.
install -d -m 755 "$STAGE/etc/systemd/journald.conf.d"
install -m 644 src/90-tachyon-camera-journald.conf \
    "$STAGE/etc/systemd/journald.conf.d/90-tachyon-camera-journald.conf"

# Hardware-encoded recording, for when Snapshot's software VP8 is too soft.
install -m 755 src/tachyon-camera-record "$STAGE/usr/bin/tachyon-camera-record"

# ---- maintainer scripts ------------------------------------------------
# Expand the manifest into explicit check_one calls. Each carries the expected
# target so preinst can tell "an old hand-made link we can adopt" from "a link
# to somewhere else", instead of skipping every symlink blindly.
checks=$(
    printf '    check_one /usr/lib/hw qcm6490/hw\n'
    printf '    check_one /usr/lib/camera qcm6490/camera\n'
    awk '!/^#/ && NF {printf "    check_one %s %s\n", $1, $2}' "$MANIFEST"
)
awk -v repl="$checks" '{ if ($0 ~ /@SYMLINK_CHECKS@/) print repl; else print }' \
    src/preinst.in > "$STAGE/DEBIAN/preinst"
cp src/postinst "$STAGE/DEBIAN/postinst"
cp src/prerm    "$STAGE/DEBIAN/prerm"
cp src/postrm   "$STAGE/DEBIAN/postrm"
chmod 755 "$STAGE/DEBIAN/preinst" "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/prerm" "$STAGE/DEBIAN/postrm"

# Normalise modes before packing. mktemp -d gives 0700 and the caller's umask
# leaks into everything created under it, so without this the package would
# carry a 0700 root and group-writable system directories.
# -type d/f never match symlinks, so the 153 links are left alone.
find "$STAGE" -type d -exec chmod 755 {} +
find "$STAGE" -type f -exec chmod 644 {} +
chmod 755 "$STAGE/DEBIAN/preinst" "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/prerm" "$STAGE/DEBIAN/postrm"
chmod 755 "$STAGE"/usr/bin/*
# The blanket 644 above catches this one too, and a non-executable ExecStart
# fails the unit at start with a bare 203/EXEC.
chmod 755 "$STAGE"/usr/libexec/*
# systemd-sleep silently skips a hook that is not executable.
chmod 755 "$STAGE"/lib/systemd/system-sleep/*

ver=$(awk '/^Version:/ {print $2}' pkg/DEBIAN/control)
deb="$OUT/tachyon-camera-camx-qcm6490_${ver}_arm64.deb"
dpkg-deb --root-owner-group --build "$STAGE" "$deb"
echo "built: $deb"
