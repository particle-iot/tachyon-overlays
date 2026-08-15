# Firmware sources

## vpu20_p1_gen2_s6.mbn

Gen2 video firmware for the Iris2 VPU on QCM6490 / SC7280. The upstream `iris`
driver requests it by a path built into its SC7280 Gen2 platform data
(`pd->fwname = "qcom/vpu/vpu20_p1_gen2_s6.mbn"`), so the file name and location
are both fixed.

Gen1 and Gen2 here name the host/firmware protocol generation, not the
hardware. The same Iris2 block runs either, and the Gen1 firmware that noble
ships (`vpu20_p1.mbn`) cannot encode on this part -- asking it to encode over
the Gen1 HFI takes the SoC down with a PSHOLD reset. Only the Gen2 firmware,
driven over the Gen2 HFI, encodes here.

- **Source**: linux-firmware, `qcom/vpu/vpu20_p1_gen2_s6.mbn`
  - https://gitlab.com/kernel-firmware/linux-firmware
  - WHENCE block `Driver: iris`, `Version: VIDEO.VPU.3.4-0059`
  - sha256 `f061733f2f0c644281b3455eb75b654932fe11083e4dfa9257dba72294a5f37f`
- **Licence**: Redistributable. See `LICENSE.qcom` and `NOTICE.qcom` in
  linux-firmware.
- **Fetched on**: 2026-08-15

Shipped as a plain file rather than `.zst`, matching the other firmware here,
so the kernel does not need `CONFIG_FW_LOADER_COMPRESS_ZSTD`.

Not present in noble's `linux-firmware` (`20240318.git3b128b60-0ubuntu2.26`) --
the firmware itself is dated Feb 2026, well after that snapshot, so it has to
be carried here.

Beware a name collision: linux-firmware also carries `vpu20_p1_gen2.mbn` as a
symlink to this same file, whereas qcom-linux 1.7 ships a *different* binary
under that name (`video-firmware.2.4.2`). The two are not interchangeable.
