#!/bin/bash
# Symlink QCA Bluetooth firmware files from /vendor/btfw (FAT32 nonhlos
# partition, mounted at boot) into /lib/firmware/updates/qca so the kernel
# firmware loader prefers the /vendor-provided files over rootfs stock.
#
# File list mirrors tools/make-nonhlos-img/{em,na}/btfw/ in the
# tachyon-quectel-bp-fw repo. The list is stable across Quectel SG560D
# releases; add new entries here if a future release ships extra
# hpnv21*.bXX patch files.
set -euo pipefail

DST=/lib/firmware/updates/qca
mkdir -p "$DST"

files=(
  hpbtfw21.tlv
  hpnv21.301
  hpnv21.302
  hpnv21_sony.302
  hpnv21.bin
  hpnv21.b5a
  hpnv21.b8b hpnv21.b8c hpnv21.b8d
  hpnv21.b98 hpnv21.b9a hpnv21.b9b hpnv21.b9e hpnv21.b9f
  hpnv21.ba0 hpnv21.ba1 hpnv21.ba2 hpnv21.ba3 hpnv21.ba4
  hpnv21.ba6 hpnv21.ba7 hpnv21.ba8 hpnv21.ba9
  hpnv21.baa hpnv21.bab hpnv21.bac hpnv21.bad
  hpnv21.bb0 hpnv21.bb1 hpnv21.bb2 hpnv21.bb3
  hpnv21.bb5 hpnv21.bb6 hpnv21.bb7 hpnv21.bb8 hpnv21.bb9
  hpnv21.bba hpnv21.bbb hpnv21.bbe
  hpnv21.b10c hpnv21.b111
  hpnv21g.301
  hpnv21g.302
  hpnv21g_sony.302
  hpnv21g.bin
  hpnv21g.b5a
  hpnv21g.b8b hpnv21g.b8c hpnv21g.b8d
  hpnv21g.b98 hpnv21g.b9a hpnv21g.b9b hpnv21g.b9e hpnv21g.b9f
  hpnv21g.ba0 hpnv21g.ba1 hpnv21g.ba2 hpnv21g.ba3 hpnv21g.ba4
  hpnv21g.ba6 hpnv21g.ba7 hpnv21g.ba8 hpnv21g.ba9
  hpnv21g.baa hpnv21g.bab hpnv21g.bac hpnv21g.bad
  hpnv21g.bb0 hpnv21g.bb1 hpnv21g.bb2 hpnv21g.bb3
  hpnv21g.bb5 hpnv21g.bb6 hpnv21g.bb7 hpnv21g.bb8 hpnv21g.bb9
  hpnv21g.bba hpnv21g.bbb hpnv21g.bbe
  hpnv21g.b10c hpnv21g.b111
)

for f in "${files[@]}"; do
  ln -sf "/vendor/btfw/$f" "$DST/$f"
done
