#!/bin/bash
# Install the vendor CamX camera stack.
#
# Order matters. qcom-fastrpc1 - which CamX pulls in - depends on
# linux-firmware-dragonwing, whose 381 files under /lib/firmware/updates would
# shadow the Particle-tuned blobs (the kernel searches that path first). The
# compat package must therefore satisfy that dependency *before* apt gets a
# chance to resolve it the upstream way.
#
# The CamX debs ship no postinst, so the per-SoC layout they expect
# (/usr/lib/hw, /usr/lib/camera, 153 links into /usr/lib/qcm6490) is missing.
# tachyon-camera-camx-qcm6490 provides it as package payload, so dpkg owns it.
set -euo pipefail

DEBDIR=/tmp/tachyon-camera-debs
ATH=/lib/firmware/updates/ath11k

die() { echo "FATAL: $*" >&2; exit 1; }

echo "### preflight"
# The compat package only satisfies a dependency - it ships no firmware. These
# are the things that actually have to be in place, so check rather than assume.
dpkg-query -W -f='${Status}' linux-firmware-dragonwing 2>/dev/null \
    | grep -q "install ok installed" \
    && die "linux-firmware-dragonwing is installed; it shadows the platform wifi firmware"

# The driver asks for qca6698aq hw2.1. On this platform that name is a link to
# WCN6855 whose contents point into /vendor - if it is anything else, the
# firmware layout is not what this stack expects.
[ -L "$ATH/QCA6698AQ" ] || die "$ATH/QCA6698AQ is not a symlink (dragonwing layout?)"
for f in amss.bin board.bin; do
    tgt=$(readlink -f "$ATH/QCA6698AQ/hw2.1/$f" 2>/dev/null || true)
    case "$tgt" in
        /vendor/wlan/*) ;;
        *) die "$ATH/QCA6698AQ/hw2.1/$f resolves to '${tgt:-nothing}', expected /vendor/wlan/*" ;;
    esac
done
[ -d /vendor/wlan ] || die "/vendor/wlan missing - is core_nhlos_a mounted?"

# CamX offloads to the CDSP through fastrpc, and the whole point of the compat
# package is that the platform - not linux-firmware-dragonwing - provides that
# firmware. If it is absent the stack installs and then never enumerates a
# camera, so fail here rather than ship something known-broken. The name is the
# remoteproc firmware property of a300000.remoteproc, not a wildcard.
for f in cdsp.mdt cdsp.mbn; do
    [ -f "/lib/firmware/qcom/qcm6490/$f" ] \
        || die "/lib/firmware/qcom/qcm6490/$f missing - CDSP cannot boot, fastrpc will not come up"
done

echo "### PPA"
if ! grep -rqs "ubuntu-qcom-iot" /etc/apt/sources.list.d/; then
    apt-get install -y --no-install-recommends software-properties-common
    add-apt-repository -y ppa:ubuntu-qcom-iot/qcom-ppa
fi
apt-get update -o Acquire::Retries=3

echo "### firmware compat provider (must precede the CamX stack)"
apt-get install -y "$DEBDIR"/tachyon-firmware-dragonwing-compat_*_all.deb

echo "### CamX integration"
# Pulls in the pinned qcom-camx / chicdk / camxlib / fastrpc closure via Depends.
apt-get install -y "$DEBDIR"/tachyon-camera-camx-qcm6490_*_arm64.deb

echo "### verify"
[ -e /usr/lib/hw/camera.qcom.so ] || die "/usr/lib/hw/camera.qcom.so missing"

# Check the sensor plugin as well as the HAL. CamX dlopen()s it long after
# startup, so a missing dependency there does not show up in the HAL's own ldd
# and surfaces only as a camera that enumerates zero devices.
for so in /usr/lib/qcm6490/hw/camera.qcom.so \
          /usr/lib/qcm6490/camera/com.qti.sensor.imx519.so; do
    [ -e "$so" ] || die "$so missing"
    # Capture first: piping ldd straight into grep hides its exit status, so a
    # file ldd cannot process at all would read as "no missing libraries".
    out=$(ldd "$so" 2>&1) || { echo "$out" >&2; die "ldd failed on $so"; }
    case "$out" in
        *"not found"*)
            echo "$out" | grep "not found" >&2
            die "unresolved shared libraries in $so" ;;
    esac
done
dpkg-divert --list | grep -q socid_map || die "socid_map diversion missing"

# dpkg --audit prints nothing when healthy; treat any output as a failure.
audit=$(dpkg --audit 2>&1)
[ -z "$audit" ] || { echo "$audit" >&2; die "dpkg database is not clean"; }
apt-get check >/dev/null 2>&1 || die "apt-get check failed"

# Wifi must still resolve into /vendor after the transaction.
tgt=$(readlink -f "$ATH/QCA6698AQ/hw2.1/board.bin" 2>/dev/null || true)
case "$tgt" in /vendor/wlan/*) ;; *) die "wifi firmware no longer resolves into /vendor" ;; esac

echo "### CamX stack installed (HAL3 only - see /usr/share/doc/tachyon-camera-camx-qcm6490/README.md)"
