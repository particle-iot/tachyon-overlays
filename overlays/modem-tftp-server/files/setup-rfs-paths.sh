#!/bin/bash
# Setup RFS (Remote File System) directory structure and symlinks
# for Qualcomm modem file access via QRTR
#
# The modem requests files using virtual RFS paths. These symlinks map
# the virtual paths to real Linux filesystem locations.

set -euo pipefail

echo "Setting up RFS directory structure for Qualcomm modem file access..."

# The readonly/firmware path differs by build layout, so branch on the same
# ENV_UBUNTU_24_04_VERSION that add-fstab-mounts uses (defaults to 1.2/new-BP).
# The default MUST match add-fstab-mounts': if fstab mounts the new-BP layout
# while this script links the 1.1 one, readonly/firmware points at a /firmware
# that was never mounted and the modem silently parks at CFUN=7.
#
#   1.1      a real /firmware partition (/dev/sdg1) is mounted, and the modem's
#            readonly tree is that mount.
#   1.2+     "new-BP": there is no /firmware partition.  The non-HLOS firmware
#            lives on core_nhlos_a, mounted at /vendor, and the modem images sit
#            in /vendor/modem.
#
# The modem asks for paths under "readonly/firmware/image/", e.g.
#   readonly/firmware/image/modem_pr/mcfg/configs/mcfg_sw/mbn_sw.dig
# and on new-BP that content is /vendor/modem/modem_pr/..., so the mapping is
# readonly/firmware/image -> /vendor/modem.  Pointing readonly/firmware at the
# leftover empty /firmware makes every one of those reads fail with ENOENT; the
# modem then never loads its MCFG and parks at CFUN=7, which surfaces to
# ModemManager and qmicli as "DeviceNotReady" with no other clue.
echo "[modem-tftp-server] read ENV_UBUNTU_24_04_VERSION='${ENV_UBUNTU_24_04_VERSION:-}' (defaults to 1.2 if empty)"
VERSION="${ENV_UBUNTU_24_04_VERSION:-1.2}"
if [ "$(printf '%s\n1.2\n' "$VERSION" | sort -V | head -n1)" = "1.2" ]; then
    NEW_BP=1
    echo "[modem-tftp-server] Ubuntu 24.04 build $VERSION -> new-BP (/vendor/modem)"
else
    NEW_BP=0
    echo "[modem-tftp-server] Ubuntu 24.04 build $VERSION -> 1.1 (/firmware)"
fi

# Point one subsystem's readonly tree at the firmware for this layout.
link_readonly_firmware() {
    _sub="$1"
    if [ "$NEW_BP" = "1" ]; then
        mkdir -p "/system/rfs/msm/$_sub/readonly/firmware"
        ln -sfn /vendor/modem "/system/rfs/msm/$_sub/readonly/firmware/image"
    else
        ln -sf /firmware/ "/system/rfs/msm/$_sub/readonly/firmware"
    fi
}

# Create base directory structure
# /system/rfs - base path for RFS virtual filesystem
# /data/persist/rfs - persistent storage for modem files
# /data/tombstones - ramdump storage for subsystem crashes

mkdir -p /system/rfs/msm/{mpss,adsp,cdsp,slpi}/readonly
mkdir -p /data/persist/rfs/msm/{mpss,adsp,cdsp,slpi,wpss}
mkdir -p /data/persist/rfs/mdm/{mpss,adsp,cdsp,slpi,wpss,tn}
mkdir -p /data/persist/rfs/apq/gnss
mkdir -p /data/persist/rfs/shared
mkdir -p /data/persist/hlos_rfs/shared
mkdir -p /data/tombstones/{modem,lpass,cdsp,slpi,tn}
mkdir -p /data/data/vendor/tombstones/rfs/{modem,lpass,cdsp,slpi,tn}

# Create modem config directories
mkdir -p /data/persist/rfs/msm/mpss/ota_firewall

# MPSS (Modem Processor SubSystem) symlinks
link_readonly_firmware mpss
ln -sf /data/persist/rfs/shared/ /system/rfs/msm/mpss/shared
ln -sf /data/persist/hlos_rfs/shared/ /system/rfs/msm/mpss/hlos
ln -sf /data/persist/rfs/msm/mpss/ /system/rfs/msm/mpss/readwrite
ln -sf /data/tombstones/modem/ /system/rfs/msm/mpss/ramdumps

# ADSP (Audio DSP) symlinks
link_readonly_firmware adsp
ln -sf /data/persist/rfs/shared/ /system/rfs/msm/adsp/shared
ln -sf /data/persist/hlos_rfs/shared/ /system/rfs/msm/adsp/hlos
ln -sf /data/persist/rfs/msm/adsp/ /system/rfs/msm/adsp/readwrite
ln -sf /data/tombstones/lpass/ /system/rfs/msm/adsp/ramdumps

# CDSP (Compute DSP) symlinks
link_readonly_firmware cdsp
ln -sf /data/persist/rfs/shared/ /system/rfs/msm/cdsp/shared
ln -sf /data/persist/hlos_rfs/shared/ /system/rfs/msm/cdsp/hlos
ln -sf /data/persist/rfs/msm/cdsp/ /system/rfs/msm/cdsp/readwrite
ln -sf /data/tombstones/cdsp/ /system/rfs/msm/cdsp/ramdumps

# SLPI (Sensor Low Power Island) symlinks
link_readonly_firmware slpi
ln -sf /data/persist/rfs/shared/ /system/rfs/msm/slpi/shared
ln -sf /data/persist/hlos_rfs/shared/ /system/rfs/msm/slpi/hlos
ln -sf /data/persist/rfs/msm/slpi/ /system/rfs/msm/slpi/readwrite
ln -sf /data/tombstones/slpi/ /system/rfs/msm/slpi/ramdumps

# Set ownership for particle user
chown -R particle:particle /system/rfs /data/persist/rfs /data/persist/hlos_rfs /data/tombstones /data/data 2>/dev/null || true

echo "RFS directory structure setup complete"
