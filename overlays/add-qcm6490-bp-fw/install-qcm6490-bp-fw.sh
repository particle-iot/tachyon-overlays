#!/bin/bash
set -euo pipefail

FW_ZIP="/tmp/QCM6490_fw.zip"
FW_DIR="/tmp/QCM6490_fw"

# Extract with the python3 stdlib, which is always present in the Ubuntu rootfs.
# The overlay chroot has no network, so apt-installing unzip is not an option.
rm -rf "${FW_DIR}"
python3 -m zipfile -e "${FW_ZIP}" /tmp/

mkdir -p /lib/firmware /usr/lib/dsp
cp -a "${FW_DIR}/lib/firmware/." /lib/firmware/
cp -a "${FW_DIR}/usr/lib/dsp/." /usr/lib/dsp/

# qcom_geni_se driver expects /lib/firmware/qupv3fw.elf
ln -sf qcom/qcm6490/qupv3fw.elf /lib/firmware/qupv3fw.elf

# Bake qupv3fw.elf into the initramfs. Otherwise, when the kernel probes
# geni_i2c / geni_spi the real rootfs is not mounted yet, the firmware is
# unavailable, and the log fills with -ENOENT / EPROBE_DEFER.
mkdir -p /etc/initramfs-tools/hooks
cat > /etc/initramfs-tools/hooks/qupv3fw <<'HOOK'
#!/bin/sh
set -e
PREREQ=""
prereqs() { echo "$PREREQ"; }
case "$1" in
  prereqs) prereqs; exit 0 ;;
esac
. /usr/share/initramfs-tools/hook-functions
mkdir -p "${DESTDIR}/lib/firmware"
# -L dereferences the symlink so the real bytes land in the initramfs
cp -aL /lib/firmware/qupv3fw.elf "${DESTDIR}/lib/firmware/qupv3fw.elf"
HOOK
chmod +x /etc/initramfs-tools/hooks/qupv3fw

update-initramfs -u
