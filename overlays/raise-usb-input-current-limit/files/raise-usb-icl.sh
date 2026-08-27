#!/bin/sh
# Raise the USB input current limit to what the port actually negotiated.
#
# The PMIC comes up at the bare SDP default of 100 mA. The board draws more than
# that at idle, so while plugged in the pack net-discharges: observed 3325 mV
# falling with battery current -60 mA, despite status reading "Charging". A flat
# pack then cannot climb past the bootloader's BootToHLOSThresholdInMv gate
# (3400 mV), so the device sits in the UEFI charging loop indefinitely.
#
# Setting the limit to current_max (read-only, what the port advertised) took the
# same board to 870 mA input / +886 mA into the battery, and vbat rose 3325 ->
# 3467 mV within five seconds.
#
# current_max is never exceeded, so this cannot ask for more than the port offers.
set -u

for psy in /sys/class/power_supply/qcom-battmgr-usb /sys/class/power_supply/usb; do
    [ -d "$psy" ] || continue

    icl="$psy/input_current_limit"
    max="$psy/current_max"
    [ -w "$icl" ] || continue
    [ -r "$max" ] || continue

    want=$(cat "$max" 2>/dev/null) || continue
    case "$want" in ''|*[!0-9]*) continue ;; esac
    [ "$want" -gt 0 ] || continue

    have=$(cat "$icl" 2>/dev/null) || have=0
    case "$have" in ''|*[!0-9]*) have=0 ;; esac

    if [ "$have" -lt "$want" ]; then
        if printf '%s\n' "$want" > "$icl" 2>/dev/null; then
            echo "raise-usb-icl: $psy input_current_limit ${have} -> ${want} uA"
        else
            echo "raise-usb-icl: failed to write ${want} to $icl" >&2
        fi
    fi
done

exit 0
