#!/bin/bash
set -euo pipefail

FW_ZIP="/tmp/QCM6490_fw.zip"
FW_DIR="/tmp/QCM6490_fw"

# Extract with the python3 stdlib, which is always present in the Ubuntu rootfs.
# The overlay chroot has no network, so apt-installing unzip is not an option.
rm -rf "${FW_DIR}"
python3 -m zipfile -e "${FW_ZIP}" /tmp/

# This overlay owns ONLY the DSP / qcom platform firmware. Copy just qcom/ (adsp,
# cdsp, qupv3fw.elf, ...) and the DSP skeleton libs - NOT the whole lib/firmware
# tree. The bp-fw zip also ships ath11k/qcacld/updates(qca) wifi+bt firmware, but
# those are provided by the link-ath11k-firmware / link-qca-bt-firmware overlays as
# symlinks into /vendor. /vendor is not mounted inside the chroot, so those symlinks
# are dangling; copying the full tree over them fails with "cp: not writing through
# dangling symlink", which trips set -e and aborts the whole build.
# --remove-destination: bp-fw files are authoritative; replace any pre-existing
# (possibly dangling) symlink with the real bytes instead of erroring out.
mkdir -p /lib/firmware/qcom /usr/lib/dsp
cp -a --remove-destination "${FW_DIR}/lib/firmware/qcom/." /lib/firmware/qcom/
cp -a --remove-destination "${FW_DIR}/usr/lib/dsp/." /usr/lib/dsp/

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
