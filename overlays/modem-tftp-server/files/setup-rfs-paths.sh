#!/bin/bash
# Setup RFS (Remote File System) directory structure and symlinks
# for Qualcomm modem file access via QRTR
#
# The modem requests files using virtual RFS paths. These symlinks map
# the virtual paths to real Linux filesystem locations.

set -euo pipefail

echo "Setting up RFS directory structure for Qualcomm modem file access..."

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
ln -sf /firmware/ /system/rfs/msm/mpss/readonly/firmware
ln -sf /data/persist/rfs/shared/ /system/rfs/msm/mpss/shared
ln -sf /data/persist/hlos_rfs/shared/ /system/rfs/msm/mpss/hlos
ln -sf /data/persist/rfs/msm/mpss/ /system/rfs/msm/mpss/readwrite
ln -sf /data/tombstones/modem/ /system/rfs/msm/mpss/ramdumps

# ADSP (Audio DSP) symlinks
ln -sf /firmware/ /system/rfs/msm/adsp/readonly/firmware
ln -sf /data/persist/rfs/shared/ /system/rfs/msm/adsp/shared
ln -sf /data/persist/hlos_rfs/shared/ /system/rfs/msm/adsp/hlos
ln -sf /data/persist/rfs/msm/adsp/ /system/rfs/msm/adsp/readwrite
ln -sf /data/tombstones/lpass/ /system/rfs/msm/adsp/ramdumps

# CDSP (Compute DSP) symlinks
ln -sf /firmware/ /system/rfs/msm/cdsp/readonly/firmware
ln -sf /data/persist/rfs/shared/ /system/rfs/msm/cdsp/shared
ln -sf /data/persist/hlos_rfs/shared/ /system/rfs/msm/cdsp/hlos
ln -sf /data/persist/rfs/msm/cdsp/ /system/rfs/msm/cdsp/readwrite
ln -sf /data/tombstones/cdsp/ /system/rfs/msm/cdsp/ramdumps

# SLPI (Sensor Low Power Island) symlinks
ln -sf /firmware/ /system/rfs/msm/slpi/readonly/firmware
ln -sf /data/persist/rfs/shared/ /system/rfs/msm/slpi/shared
ln -sf /data/persist/hlos_rfs/shared/ /system/rfs/msm/slpi/hlos
ln -sf /data/persist/rfs/msm/slpi/ /system/rfs/msm/slpi/readwrite
ln -sf /data/tombstones/slpi/ /system/rfs/msm/slpi/ramdumps

# Set ownership for particle user
chown -R particle:particle /system/rfs /data/persist/rfs /data/persist/hlos_rfs /data/tombstones /data/data 2>/dev/null || true

echo "RFS directory structure setup complete"
