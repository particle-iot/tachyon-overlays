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
OUT=${1:-.}
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
REQUIRED_TOOLS="camx-enum camx-capture"

for f in $REQUIRED_CAMERA; do
    [ -f "assets/camera/$f" ] || { echo "missing asset: assets/camera/$f" >&2; exit 1; }
done
for f in $REQUIRED_TOOLS; do
    [ -f "assets/tools/$f" ] || { echo "missing tool: assets/tools/$f" >&2; exit 1; }
done
for f in $REQUIRED_DTBO; do
    [ -f "assets/dtbo/$f" ] || { echo "missing dtbo: assets/dtbo/$f" >&2; exit 1; }
done

# The sensor plugin is a prebuilt vendor artifact that build-assets.sh patches,
# so validate it positively rather than only looking for the one known defect.
# Checking "does not contain libsync" alone passes for a truncated file, an
# x86 build, or anything readelf cannot parse at all.
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
# sensor is silently absent from enumeration.
dyn=$(readelf -dW "$PLUGIN") || { echo "$PLUGIN: cannot read .dynamic" >&2; exit 1; }
syms=$(readelf -sW --dyn-syms "$PLUGIN") || { echo "$PLUGIN: cannot read .dynsym" >&2; exit 1; }
case "$syms" in
    *GetSensorLibraryAPIs*) ;;
    *) echo "$PLUGIN: does not export GetSensorLibraryAPIs" >&2; exit 1 ;;
esac

# The stock plugin carries a DT_NEEDED on libsync.so.0 that nothing on this
# platform provides. It is a dead dependency: the CamX build system put -lsync
# into CMAKE_CXX_FLAGS ahead of --as-needed, so it got recorded even though the
# plugin references no sync_*/fence symbol at all. Verified - zero undefined
# sync symbols, and the camera enumerates and captures fine on a system with no
# libsync present. build-assets.sh strips it; assets must ship without it.
case "$dyn" in
    *libsync*)
        echo "$PLUGIN: still has DT_NEEDED libsync.so.0" >&2
        echo "  run ./build-assets.sh, which strips it" >&2
        echo "  (preferred long-term fix: rebuild the plugin without -lsync)" >&2
        exit 1 ;;
esac

install -d -m 755 "$STAGE/usr/lib/qcm6490/camera"
install -m 644 assets/camera/* "$STAGE/usr/lib/qcm6490/camera/"
install -d -m 755 "$STAGE/usr/share/tachyon/dtbo"
install -m 644 assets/dtbo/* "$STAGE/usr/share/tachyon/dtbo/"
install -d -m 755 "$STAGE/usr/bin"
install -m 755 assets/tools/* "$STAGE/usr/bin/"
echo "staged $(ls -1 assets/camera | wc -l) camera assets, $(ls -1 assets/tools | wc -l) tools, $(ls -1 assets/dtbo | wc -l) dtbo"

# /var/cache/camera via tmpfiles, not by relying on CamX's first root run
install -d -m 755 "$STAGE/usr/lib/tmpfiles.d"
install -m 644 src/tachyon-camera.tmpfiles "$STAGE/usr/lib/tmpfiles.d/tachyon-camera.conf"

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
cp src/postrm   "$STAGE/DEBIAN/postrm"
chmod 755 "$STAGE/DEBIAN/preinst" "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/postrm"

# Normalise modes before packing. mktemp -d gives 0700 and the caller's umask
# leaks into everything created under it, so without this the package would
# carry a 0700 root and group-writable system directories.
# -type d/f never match symlinks, so the 153 links are left alone.
find "$STAGE" -type d -exec chmod 755 {} +
find "$STAGE" -type f -exec chmod 644 {} +
chmod 755 "$STAGE/DEBIAN/preinst" "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/postrm"
chmod 755 "$STAGE"/usr/bin/*

ver=$(awk '/^Version:/ {print $2}' pkg/DEBIAN/control)
deb="$OUT/tachyon-camera-camx-qcm6490_${ver}_arm64.deb"
dpkg-deb --root-owner-group --build "$STAGE" "$deb"
echo "built: $deb"
