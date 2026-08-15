#!/bin/bash
# Regenerate the camera assets in assets/ from the sources in src/.
#
# Needs two external trees that are not part of this repo, so the built
# artifacts are committed and this script is the way to reproduce them:
#
#   CHICDK  a chi-cdk tree providing ParameterParser. It MUST be V5.5.1 - the
#           repack CamX stack cannot read bins written by the V5.0.2 parser
#           that ships with the kt stack, even though both stamp format
#           version 5 in the header.
#   KERNEL  the Tachyon kernel tree, for the dtc include paths.
#
#   CHICDK=/path/to/chi-cdk KERNEL=/path/to/kernel ./build-assets.sh
set -euo pipefail
cd "$(dirname "$0")"

CHICDK=${CHICDK:-/home/yuting/yytdisk/projects/tachyon-quectel-bp-fw/LE.QCLINUX.1.0.r1/apps_proc/sources/vendor/qcom/proprietary/chi-cdk-kt}
KERNEL=${KERNEL:-/home/yuting/yytdisk/projects/tachyon-prj/tachyon-ubuntu-24.04-kernel-fork}
PP="$CHICDK/tools/buildbins/linux64/ParameterParser"

# Pinned so a different chi-cdk drop cannot silently produce bins the runtime
# stack rejects. Both parsers stamp format version 5 in the header, so a
# mismatch shows up only as a sensor that fails to load. See PROVENANCE.md.
PP_VERSION="Parameter Parser V5.5.1 (2411131018)"
PP_SHA256=2724822ab1ce93089e050414ee1b85fa8eb0a45dcc1bb0face0c7b4a3a792be3

[ -x "$PP" ] || { echo "ParameterParser not found: $PP" >&2; exit 1; }

# The space after $( matters: "$((" would be parsed as an arithmetic expansion.
have_ver=$( ("$PP" 2>&1 || true) | grep -i "parameter parser" | head -1 )
have_sha=$(sha256sum "$PP" | cut -d' ' -f1)
if [ "$have_ver" != "$PP_VERSION" ] || [ "$have_sha" != "$PP_SHA256" ]; then
    echo "ParameterParser does not match the pinned build:" >&2
    echo "  want: $PP_VERSION  $PP_SHA256" >&2
    echo "  have: ${have_ver:-<no version line>}  $have_sha" >&2
    exit 1
fi
echo "== ParameterParser: $have_ver =="

# ---- actuator semantic gate ---------------------------------------------
# These five fields decide whether the VCM actually moves, and getting any of
# them wrong produces a perfectly valid bin whose only symptom is that focus
# silently never changes - every I2C write still ACKs, no error is logged.
# That cost days once; the values come from Qualcomm's own ak7375_actuator.xml.
ACT=src/xml/tachyon_ak7375_actuator.xml
act_expect() {   # <xpath-ish tag> <expected> <why>
    got=$(grep -oP "(?<=<$1>)[^<]*" "$ACT" | head -1)
    [ "$got" = "$2" ] && return 0
    echo "$ACT: <$1> is '${got:-<missing>}', expected '$2'" >&2
    echo "  $3" >&2
    return 1
}
fail=0
act_expect actuatorType   BIVCM "AK7375 is bi-directional; VCM drives it wrong"      || fail=1
act_expect dataBitWidth   10    "AK7375 takes 10-bit codes, not 12"                  || fail=1
act_expect dataShift      6     "10-bit values sit at bit[15:6]; shift 4 misplaces them" || fail=1
act_expect macroStepBoundary 400 "CamX MaxSteps=400; above it the step table is never built" || fail=1
# init must be WRITE 0x02 (leave standby) followed by POLL 0x02 (wait ready)
ops=$(sed -n '/<initSettings>/,/<\/initSettings>/p' "$ACT" | grep -oP "(?<=<operation>)[^<]*" | paste -sd, -)
[ "$ops" = "WRITE,POLL" ] || {
    echo "$ACT: initSettings operations are '${ops:-none}', expected 'WRITE,POLL'" >&2
    echo "  the POLL waits for the VCM to leave standby before any DAC write" >&2
    fail=1
}
[ "$fail" -eq 0 ] || { echo "actuator config gate failed - refusing to build" >&2; exit 1; }
echo "== actuator: BIVCM/10-bit/shift6/steps400/WRITE+POLL =="

# ---- sensormodule + socid_map bins -------------------------------------
# The XSD paths inside the XML are relative (..\..\..\api\sensor\), so the
# parser has to run from a directory laid out like oem/qcom/module.
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/oem/qcom/module" "$WORK/oem/qcom/sensor/imx519" "$WORK/oem/qcom/actuator"
cp src/xml/tachyon_imx519_sensor.xml   "$WORK/oem/qcom/sensor/imx519/"
cp src/xml/tachyon_ak7375_actuator.xml "$WORK/oem/qcom/actuator/"
cp src/xml/tachyon_imx519_csi1_module.xml src/xml/tachyon_imx519_csi2_module.xml \
   src/xml/tachyon_socid_map.xml "$WORK/oem/qcom/module/"
ln -s "$CHICDK/api" "$WORK/api" 2>/dev/null || cp -r "$CHICDK/api" "$WORK/api"

# One bin per connector. They differ only in cameraId - the slot CamX matches a
# probed sensor against - so the same sensor and actuator XML feed both.
(
  cd "$WORK/oem/qcom/module"
  for port in csi1 csi2; do
    # Input order fixes the section order inside the bin: sensor, module, actuator.
    "$PP" "com.qti.sensormodule.tachyon_imx519_${port}_4lane.bin" b \
          ../sensor/imx519/tachyon_imx519_sensor.xml \
          "tachyon_imx519_${port}_module.xml" \
          ../actuator/tachyon_ak7375_actuator.xml | tail -2
  done
  "$PP" com.qti.sensorsocmap.socid_map.bin b tachyon_socid_map.xml | tail -2
)

install -d -m 755 assets/camera
for port in csi1 csi2; do
    install -m 644 "$WORK/oem/qcom/module/com.qti.sensormodule.tachyon_imx519_${port}_4lane.bin" \
            assets/camera/
done
install -m 644 "$WORK/oem/qcom/module/com.qti.sensorsocmap.socid_map.bin"  assets/camera/

# ---- device tree overlays -----------------------------------------------
# One dtbo per connector. They are independent components: the user picks
# either, or lists both for dual-camera operation.
install -d -m 755 assets/dtbo "$WORK/dt"
cp src/dts/*.dtsi src/dts/*.dtso "$WORK/dt/"
# The camera bindings must come from the stack that actually owns this SoC.
# ubuntu/qcom/camera/Kbuild selects camera_kt for qcm6490 (its objects are
# camera_kt/drivers/*.o), so camera_kt/dt-bindings is the ABI the loaded
# camera_qcm6490.ko was built against.
#
# The merged include/dt-bindings/msm-camera.h concatenates both stacks' macros
# with conflicting values - CAM_CPAS_SHDR_FUSE is 7 in camera_kt and 12 in the
# other - and cpp silently takes the last definition. Putting the stack's own
# directory first resolves this without touching a header two stacks share.
CAM_BINDINGS="$KERNEL/ubuntu/qcom/camera/camera_kt"
[ -f "$CAM_BINDINGS/dt-bindings/msm-camera.h" ] \
    || { echo "camera_kt bindings not found under $CAM_BINDINGS" >&2; exit 1; }

for port in csi1 csi2; do
  (
    cd "$WORK/dt"
    # stderr is kept: cpp include errors and dtc's overlay/unit-address warnings
    # are exactly what a silent 2>/dev/null hides until the board fails to boot.
    cpp -nostdinc -I. -I"$CAM_BINDINGS" -I"$KERNEL/include" \
        -I"$KERNEL/scripts/dtc/include-prefixes" \
        -undef -D__DTS__ -x assembler-with-cpp \
        "qcm6490-tachyon-vendor-camera-imx519-${port}.dtso" -o "${port}.pp"
    dtc -@ -I dts -O dtb -o "${port}.dtbo" "${port}.pp"
  )
  install -m 644 "$WORK/dt/${port}.dtbo" \
          "assets/dtbo/combined-dtb-vendor-camera-imx519-${port}-4lane.dtbo"
done

# dtc only proves each overlay is well-formed. Whether one actually applies
# depends on the base tree it will be merged against at boot, and a symbol that
# does not resolve there fails at boot with the overlay silently skipped.
# Point BASE_DTB at the combined-dtb.dtb from /boot/dtb_a to check that here.
BASE_DTB=${BASE_DTB:-}
if [ -n "$BASE_DTB" ]; then
    [ -f "$BASE_DTB" ] || { echo "BASE_DTB not found: $BASE_DTB" >&2; exit 1; }

    check_merged() {   # $1 = label, rest = dtbo list
        label=$1; shift
        fdtoverlay -i "$BASE_DTB" -o "$WORK/dt/merged.dtb" "$@" \
            || { echo "overlay set '$label' does not apply to $BASE_DTB" >&2; exit 1; }
        # Applying cleanly is necessary but not sufficient - a fragment whose
        # target does not resolve is dropped without complaint. cam-req-mgr is
        # the node behind /dev/video0, so its presence is what "CamX is wired
        # up" means.
        for node in qcom,cam-req-mgr qcom,cam-isp qcom,cam-cpas; do
            fdtget -l "$WORK/dt/merged.dtb" "/soc@0/$node" >/dev/null 2>&1 \
                || { echo "'$label': merged tree has no /soc@0/$node" >&2; exit 1; }
        done
    }

    C1=assets/dtbo/combined-dtb-vendor-camera-imx519-csi1-4lane.dtbo
    C2=assets/dtbo/combined-dtb-vendor-camera-imx519-csi2-4lane.dtbo
    check_merged csi1 "$C1"
    check_merged csi2 "$C2"
    # Both at once must work too - the two overlays duplicate the camera base
    # blocks, and that only merges cleanly while the duplicated content stays
    # byte-identical. This check is what catches the two drifting apart.
    check_merged "csi1+csi2" "$C1" "$C2"
    for slot in "qcom,cci1/qcom,cam-sensor0" "qcom,cci0/qcom,cam-sensor1"; do
        fdtget -l "$WORK/dt/merged.dtb" "/soc@0/$slot" >/dev/null 2>&1 \
            || { echo "dual-camera tree lost /soc@0/$slot" >&2; exit 1; }
    done
    echo "== overlays apply to $(basename "$BASE_DTB"): csi1, csi2, and both together =="
else
    echo "== skipping fdtoverlay check (set BASE_DTB=/path/to/combined-dtb.dtb) =="
fi

# ---- prebuilt vendor sensor plugin --------------------------------------
# vendor/com.qti.sensor.imx519.so is a Qualcomm binary that no PPA package
# ships (qcom-chicdk-qcm6490 carries eight sensor plugins, IMX519 is not among
# them). It needs one edit before it can be used here, so derive the asset
# rather than committing a hand-patched copy nobody can reproduce.
#
# The edit: drop DT_NEEDED libsync.so.0. Nothing on this platform provides
# that library and the plugin references no symbol from it - the CamX build
# put -lsync into CMAKE_CXX_FLAGS ahead of --as-needed, so the linker recorded
# a dependency with zero references. See PROVENANCE.md.
SRC_PLUGIN=vendor/com.qti.sensor.imx519.so
DST_PLUGIN=assets/camera/com.qti.sensor.imx519.so
SRC_PLUGIN_SHA256=124ec7e85ec82a6d90779ab1de5a1ea725c38f7373ca5af19eedc74e2b0dd824
PLUGIN_TEXT_SHA256=97ffea788e76af547fd024aa28508bf6c48b41a780902bfadc97127322e6c005
# The exact bytes this script is known to produce. patchelf 0.18.0 rewrites
# .dynamic in place, so the output is reproducible; a mismatch means either a
# different patchelf or a different input, and both deserve a look before the
# result ships.
DST_PLUGIN_SHA256=c2a77eda3837d08150155c1f7bc88fae6616904620682af5498dd28c304ce5a4
SRC_TUNING=vendor/com.qti.tuned.sunny_imx519.bin
SRC_TUNING_SHA256=56003d9d5323c57ff97946928646ca947176b107d80d4f4be4488ce8ed447737

# Hex offsets come out of readelf; convert in the shell rather than with awk's
# strtonum(), which is a gawk extension that mawk - equally likely to be
# /usr/bin/awk on Ubuntu - does not implement.
text_sha() {
    off=$(readelf -SW "$1" | awk '$2==".text"{print $5}')
    sz=$(readelf -SW "$1" | awk '$2==".text"{print $6}')
    [ -n "$off" ] && [ -n "$sz" ] || { echo "$1: no .text section" >&2; return 1; }
    dd if="$1" bs=1 skip=$((0x$off)) count=$((0x$sz)) status=none | sha256sum | cut -d' ' -f1
}

command -v patchelf >/dev/null || { echo "patchelf not installed" >&2; exit 1; }

check_sha() {
    have=$(sha256sum "$1" | cut -d' ' -f1)
    [ "$have" = "$2" ] && return 0
    echo "$1 does not match its recorded hash" >&2
    echo "  want $2" >&2
    echo "  have $have" >&2
    return 1
}
check_sha "$SRC_PLUGIN" "$SRC_PLUGIN_SHA256" || exit 1
check_sha "$SRC_TUNING" "$SRC_TUNING_SHA256" || exit 1

cp "$SRC_PLUGIN" "$WORK/plugin.so"
patchelf --remove-needed libsync.so.0 "$WORK/plugin.so"

# patchelf rewrites .dynamic in place; the code must come through untouched.
# Comparing .text rather than the whole file keeps this check independent of
# the patchelf version, which is free to lay out the rest differently.
got=$(text_sha "$WORK/plugin.so")
[ "$got" = "$PLUGIN_TEXT_SHA256" ] || {
    echo "patchelf altered .text - refusing to ship" >&2
    echo "  want $PLUGIN_TEXT_SHA256" >&2
    echo "  have $got" >&2
    exit 1
}
readelf -dW "$WORK/plugin.so" | grep -q libsync && { echo "libsync still present" >&2; exit 1; }
readelf -sW --dyn-syms "$WORK/plugin.so" | grep -q GetSensorLibraryAPIs \
    || { echo "GetSensorLibraryAPIs lost" >&2; exit 1; }
check_sha "$WORK/plugin.so" "$DST_PLUGIN_SHA256" || {
    echo "  (patchelf $(patchelf --version 2>&1 | awk '{print $2}') produced different bytes;" >&2
    echo "   the semantic checks above still passed, so update DST_PLUGIN_SHA256" >&2
    echo "   deliberately if this is an intended toolchain change)" >&2
    exit 1
}
install -m 644 "$WORK/plugin.so" "$DST_PLUGIN"
echo "== sensor plugin: libsync stripped, .text unchanged, output hash pinned =="

# Tuning data needs no edit, but keep it flowing through vendor/ too so every
# shipped asset has one recorded upstream.
install -m 644 "$SRC_TUNING" assets/camera/

# ---- smoke-test clients -------------------------------------------------
# They only dlopen the HAL, so they need no vendor headers and cross-compile
# with the stock toolchain.
CC=${CC:-aarch64-linux-gnu-gcc}
command -v "$CC" >/dev/null || { echo "$CC not found" >&2; exit 1; }
install -d -m 755 assets/tools
for t in camx-enum camx-capture; do
    "$CC" -O2 -Wall -Wextra -o "assets/tools/$t" "src/$t.c" -ldl -lpthread
done
echo "== tools built with $("$CC" -dumpversion) =="

echo
echo "== assets =="
ls -la assets/camera assets/dtbo assets/tools
