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
#
# readlink -m, not -f: -f requires every component to exist, and /vendor is
# mounted at runtime, so at image build time the target is not there yet. What
# is being checked is where the link points, not whether the file is present.
for f in amss.bin board.bin; do
    tgt=$(readlink -m "$ATH/QCA6698AQ/hw2.1/$f" 2>/dev/null || true)
    case "$tgt" in
        /vendor/wlan/*) ;;
        *) die "$ATH/QCA6698AQ/hw2.1/$f resolves to '${tgt:-nothing}', expected /vendor/wlan/*" ;;
    esac
done

# On a device an empty /vendor is a real fault - every link above would dangle
# and wifi would not come up. In a chroot nothing mounts it and never will, so
# the check can only run on the device. Comparing / against pid 1's root is the
# standard way to tell the two apart.
if [ "$(stat -c %d:%i /)" = "$(stat -c %d:%i /proc/1/root/.)" ]; then
    [ -d /vendor/wlan ] || die "/vendor/wlan missing - is core_nhlos_a mounted?"
else
    echo "chroot: skipping the /vendor mount check, nothing mounts it here"
fi

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
# Retries on every fetch, not just apt-get update. The archive returned a bare
# 503 for dkms_3.0.11-1ubuntu13_all.deb once, mid-transaction, and without a
# retry that ends the whole image build over a transient mirror hiccup.
APT_OPTS="-o Acquire::Retries=3"

if ! grep -rqs "ubuntu-qcom-iot" /etc/apt/sources.list.d/; then
    apt-get install -y $APT_OPTS --no-install-recommends software-properties-common
    add-apt-repository -y ppa:ubuntu-qcom-iot/qcom-ppa
fi
apt-get update $APT_OPTS

echo "### firmware compat provider (must precede the CamX stack)"
apt-get install -y $APT_OPTS "$DEBDIR"/tachyon-firmware-dragonwing-compat_*_all.deb

echo "### CamX integration"
# Pulls in the pinned qcom-camx / chicdk / camxlib / fastrpc closure via Depends.
#
# Simulate first, and refuse if the plan contains another kernel.
# v4l2loopback-modules is a virtual package that every Ubuntu linux-modules-*
# provides, and apt did once satisfy it by scheduling a 208 MB
# linux-modules-6.8.0-1046-nvidia-lowlatency-64k into the image instead of
# building the real v4l2loopback-dkms. The Depends now names the real package
# first, so that particular route is closed - but a camera stack that drags in
# a kernel by any route is worth failing on rather than shipping, and the plan
# is right there to be read.
plan=$(apt-get install -y $APT_OPTS --simulate "$DEBDIR"/tachyon-camera-camx-qcm6490_*_arm64.deb) \
    || { echo "$plan" >&2; die "apt cannot resolve the CamX stack"; }
if printf '%s\n' "$plan" | grep -qE '^Inst (linux-image|linux-modules|linux-headers)'; then
    printf '%s\n' "$plan" | grep -E '^Inst (linux-image|linux-modules|linux-headers)' >&2
    die "installing the CamX stack would pull in another kernel"
fi

apt-get install -y $APT_OPTS "$DEBDIR"/tachyon-camera-camx-qcm6490_*_arm64.deb

echo "### verify"
[ -e /usr/lib/hw/camera.qcom.so ] || die "/usr/lib/hw/camera.qcom.so missing"

# v4l2loopback comes in through the Depends, either prebuilt in the kernel
# package or compiled here by dkms. A dkms build that fails does not fail the
# apt transaction, so look for the module itself: without it the bridge service
# installs fine and then dies at modprobe on the board, several layers from the
# cause. modinfo needs -k because uname -r in a chroot reports the build host's
# kernel, not the image's.
kdirs=(/lib/modules/*/)
[ "${#kdirs[@]}" -eq 1 ] || die "expected exactly one kernel in /lib/modules, found ${#kdirs[@]}"
KVER=$(basename "${kdirs[0]}")
modinfo -k "$KVER" v4l2loopback >/dev/null 2>&1 \
    || die "v4l2loopback is not available for $KVER - camx-v4l2-bridge cannot start"

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

# A package postinst that gates `systemctl enable` on /run/systemd/system works
# on a live board but silently leaves Composer images disabled: image chroots
# have no running system manager. The package uses deb-systemd-helper, which
# must create this state offline. Refuse the image if first boot would not
# start the bridge automatically.
service=tachyon-camera-bridge.service
enabled=/etc/systemd/system/multi-user.target.wants/$service
[ -L "$enabled" ] || die "$service is not enabled for first boot"
[ "$(readlink -f "$enabled")" = "$(readlink -f "/lib/systemd/system/$service")" ] \
    || die "$enabled does not resolve to the packaged service"

# dpkg --audit prints nothing when healthy; treat any output as a failure.
audit=$(dpkg --audit 2>&1)
[ -z "$audit" ] || { echo "$audit" >&2; die "dpkg database is not clean"; }
apt-get check >/dev/null 2>&1 || die "apt-get check failed"

# Wifi must still resolve into /vendor after the transaction. Same -m as in
# preflight: -f wants the target to exist, and /vendor is only mounted on the
# device. What is being verified is that the link still points where it did,
# which is exactly what a dragonwing install would have changed.
tgt=$(readlink -m "$ATH/QCA6698AQ/hw2.1/board.bin" 2>/dev/null || true)
case "$tgt" in /vendor/wlan/*) ;; *) die "wifi firmware no longer resolves into /vendor" ;; esac

echo "### CamX stack installed; V4L2 bridge enabled for first boot (stop it before direct HAL3 use)"
