# Firmware sources

## a660_sqe.fw, a660_gmu.bin

Adreno A660 GPU SQE (sequencer microcontroller) and GMU (GPU management unit)
firmware. Required by `msm/adreno` driver -- paths are hard-coded in
`drivers/gpu/drm/msm/adreno/a6xx_catalog.c` (see `[ADRENO_FW_SQE] = "a660_sqe.fw"`)
with a `qcom/` prefix added by the firmware loader. dts cannot override.

- **Source**: Ubuntu 24.04 `linux-firmware` package `20240318.git3b128b60-0ubuntu2.26`
  - `/lib/firmware/qcom/a660_sqe.fw.zst`
  - `/lib/firmware/qcom/a660_gmu.bin.zst`
- **Extraction**: `zstd -d <file>.zst -o <file>`
- **Extracted on**: 2026-05-08

The shipped files are uncompressed (`.fw` / `.bin`), not the `.zst` form, to
avoid relying on `CONFIG_FW_LOADER_COMPRESS_ZSTD` in the kernel build.

## a660_zap.{b00,b01,b02,elf,mdt}

ZAP (Zero-Allocation-Page) shader, signed. Loaded via the `gpu_zap_shader`
device-tree node's `firmware-name = "a660_zap.mdt"` field, hence the
non-`qcom/`-prefixed install path under `/lib/firmware/updates/`.

- **Source**: Particle `tachyon-firmware` deb (originally
  `/lib/firmware/updates/tachyon/a660_zap.*` in the legacy yyt-rootfs build)
- **Note**: not from upstream `linux-firmware` -- `dpkg -S` on the host file
  reports no package owner.
