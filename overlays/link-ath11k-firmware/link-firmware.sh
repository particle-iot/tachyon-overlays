#!/bin/bash
set -euo pipefail

DST=/lib/firmware/updates/ath11k/QCA6698AQ/hw2.1
mkdir -p "$DST"

ln -sf /vendor/wlan/amss20.bin "$DST/amss.bin"
ln -sf /vendor/wlan/amss20.bin "$DST/amss20.bin"
ln -sf /vendor/wlan/m3.bin     "$DST/m3.bin"
ln -sf /vendor/wlan/regdb.bin  "$DST/regdb.bin"
ln -sf /vendor/wlan/bdwlang.elf "$DST/board.bin"
