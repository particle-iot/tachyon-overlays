#!/bin/bash
# Tighten the modem's RF configuration to what the board can actually do.
#
# Both Tachyon variants have two antennas, but modem NV enables 4x4 MIMO on NR5G
# and LTE by default, which raises the packet loss rate. NA boards additionally
# have to run at reduced TX power for FCC certification; EM boards stay at the
# default.
#
# Runs from the first-boot service on units already in the field, and directly
# on the production line. It never resets the modem itself -- NV changes only
# take effect after a reset, and the caller decides when that happens:
#
#   0   already configured, nothing written
#   10  NV written, a reset is needed
#   1   error
set -uo pipefail

DEV=/dev/smd8
AT_TIMEOUT=3
READY_TIMEOUT=60

NR5G_NV='/nv/item_files/modem/nr5g/RRC/num_rx_cfg'
NR5G_2X2='0102'
LTE_NV='/nv/item_files/modem/lte/rrc/efs/disable_4l_per_band'
LTE_NO_4X4='FFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000000000000000'

CHANGED=0
RESP=''

log() { echo "modem-rf-config: $*"; }
die() { echo "modem-rf-config: ERROR: $*" >&2; exit 1; }

# Send one AT command; collect everything up to OK/ERROR into RESP.
#   0  got a reply
#   1  no reply within AT_TIMEOUT
#   2  the channel is gone -- reopen it before trying again
send() {
  local line deadline rc
  RESP=''
  while read -r -t 0.2 -u 3 line 2>/dev/null; do :; done   # drop leftovers
  # Same as the read below: the return code already says the channel died, the
  # kernel's "Connection reset by peer" on stderr is just noise in the journal.
  printf '%s\r\n' "$1" > "$DEV" 2>/dev/null || return 2
  deadline=$(( SECONDS + AT_TIMEOUT ))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if read -r -t 1 -u 3 line 2>/dev/null; then
      line="${line%$'\r'}"
      [ -z "$line" ] && continue
      RESP+="$line"$'\n'
      case "$line" in OK|ERROR|+CME\ ERROR:*|+CMS\ ERROR:*) return 0 ;; esac
    else
      rc=$?
      # bash returns >128 when read times out. Anything else means the fd died:
      # the modem resets itself after AT+QTXPWR=1 and takes /dev/smd8 with it.
      # Without this check the loop spins on the dead fd instead of waiting.
      [ "$rc" -gt 128 ] || return 2
    fi
  done
  return 1
}

# Reopen /dev/smd8 after the modem has taken it down.
reopen_channel() {
  exec 3<&- 2>/dev/null || true
  exec 3< "$DEV" 2>/dev/null || return 1
}

# The modem may not be up yet at boot, and particle-tachyon-rild may be holding
# the AT channel (see overlays/manufacturing/files/send-at-command.sh:12-15).
# Both look the same from here -- no clean OK -- so wait for one before writing
# any NV.
wait_for_modem() {
  local started=$SECONDS deadline=$(( SECONDS + READY_TIMEOUT )) rc
  while [ "$SECONDS" -lt "$deadline" ]; do
    send 'AT'; rc=$?
    if [ "$rc" -eq 0 ] && grep -q '^OK$' <<<"$RESP"; then
      log "modem answered after $(( SECONDS - started ))s"
      return 0
    fi
    [ "$rc" -eq 2 ] && reopen_channel
    sleep 2
  done
  die "no answer from the modem on $DEV after ${READY_TIMEOUT}s"
}

# NA or EM, read out of the firmware string the same way
# overlays/manufacturing/files/read-region.sh:16-32 does.
detect_variant() {
  local fw v
  send 'AT+GMR' || die "AT+GMR timed out"
  fw=$(grep -o 'SG560D[A-Z0-9]*' <<<"$RESP" | head -1)
  [ -n "$fw" ] || die "no SG560D firmware string in: $(tr '\n' ' ' <<<"$RESP")"
  v=${fw:6:2}
  case "$v" in
    NA|EM) echo "$v" ;;
    # Anything else and we cannot tell the variants apart. Stop rather than
    # guess -- lowering TX power on an EM board is a regression.
    *) die "expected NA or EM in '$fw', got '$v'" ;;
  esac
}

# The modem resets itself asynchronously -- AT+QTXPWR=1 does it, and a modem in
# a crash loop does it over and over -- so a command can die mid-sequence even
# though the channel was fine a moment ago. Give it one chance to come back.
recover_channel() {
  log "channel dropped; waiting for the modem to come back"
  reopen_channel || return 1
  wait_for_modem
}

# Read one NV file, printing its hex value.
#   0  read a value
#   1  the file does not exist -- the modem is using its default
#   2  the channel stopped answering
#
# QNVFR is available on this firmware (reading /nv/item_files/ims/IMS_enable
# returns a value), so an ERROR here means the file is absent, not that the
# command is unsupported.
read_nv() {
  send "AT+QNVFR=\"$1\"" || return 2   # both timeout and dead channel land here
  grep -q 'ERROR' <<<"$RESP" && return 1
  local v
  # The response can share a line with the echo, so do not anchor to line start.
  v=$(grep -o '+QNVFR: *[0-9A-Fa-f]*' <<<"$RESP" | head -1 | grep -o '[0-9A-Fa-f]*$')
  # An OK we cannot parse a value out of is treated as absent, which makes the
  # caller write the value rather than assume it is already right.
  [ -n "$v" ] || return 1
  echo "$v"
}

# Write an NV file only when it does not already hold the wanted value.
# Writing the same value twice is accepted by the modem, but skipping it keeps
# re-runs free of NV writes and lets the caller trust the exit code.
ensure_nv() {
  local path="$1" want="$2" label="$3" have rc
  have=$(read_nv "$path"); rc=$?
  if [ "$rc" -eq 2 ]; then
    recover_channel
    have=$(read_nv "$path"); rc=$?
  fi
  [ "$rc" -eq 2 ] && die "$label: the modem stopped answering"
  if [ "$rc" -eq 0 ] && [ "${have^^}" = "${want^^}" ]; then
    log "$label: already correct"
    return 0
  fi
  if [ "$rc" -eq 1 ]; then
    log "$label: not set, writing $want"
  else
    log "$label: is $have, writing $want"
  fi
  send "AT+QNVFW=\"$path\",$want" || die "$label: write timed out"
  grep -q 'ERROR' <<<"$RESP" && die "$label: the modem rejected the write"
  CHANGED=1
}

# NA only. Checked before anything is written, so a firmware that cannot do what
# FCC requires fails with the board untouched -- writing the MIMO items first and
# dying here would leave them written but unreported: die() exits 1, the caller
# never sees the 10 that says "reset needed", and the reset never happens.
require_tx_power_support() {
  local rc
  send 'AT+QTXPWR?'; rc=$?
  if [ "$rc" -ne 0 ]; then
    [ "$rc" -eq 2 ] && recover_channel
    send 'AT+QTXPWR?'; rc=$?
  fi
  [ "$rc" -eq 0 ] || die "AT+QTXPWR? got no answer"
  # A firmware without this command cannot reduce TX power at all. Fail loudly
  # rather than let an NA board ship at full power.
  grep -q 'ERROR' <<<"$RESP" && die "AT+QTXPWR is not supported by this firmware; an NA board needs a newer modem build"
  return 0
}

# NA only -- FCC certification requires the reduced level. EM boards stay at the
# default, so this is never called for them.
#
# AT+QTXPWR=1 makes the modem reset itself -- verified on an NA board, where
# dmesg showed remoteproc0 recovering right after the write and /dev/smd8 went
# away with it. The new level is already in effect once it comes back, so this
# is the last thing main() does; nothing after it would find a live channel.
ensure_tx_power() {
  local rc
  # Re-read rather than trusting the RESP left by require_tx_power_support: the
  # MIMO writes happen in between, and a write can leave the modem briefly
  # unresponsive, so a plain timeout is worth one retry too.
  send 'AT+QTXPWR?'; rc=$?
  if [ "$rc" -ne 0 ]; then
    [ "$rc" -eq 2 ] && recover_channel
    send 'AT+QTXPWR?'; rc=$?
  fi
  [ "$rc" -eq 0 ] || die "AT+QTXPWR? got no answer"
  grep -q 'ERROR' <<<"$RESP" && die "AT+QTXPWR stopped working after the NV writes"
  if grep -q '+QTXPWR: *1' <<<"$RESP"; then
    log "tx power: already reduced"
    return 0
  fi
  log "tx power: reducing"
  send 'AT+QTXPWR=1' || die "AT+QTXPWR=1 timed out"
  grep -q 'ERROR' <<<"$RESP" && die "the modem rejected AT+QTXPWR=1"
  CHANGED=1
}

main() {
  [ -c "$DEV" ] || die "$DEV is not a character device"
  exec 3< "$DEV" || die "cannot open $DEV"
  trap 'exec 3<&-' EXIT

  wait_for_modem

  local variant
  # die() inside a command substitution only exits the subshell, hence || exit.
  variant=$(detect_variant) || exit 1
  log "variant: $variant"

  # Capability check before the first write, so an NA board on a firmware that
  # cannot reduce TX power is left untouched instead of half-configured.
  [ "$variant" = NA ] && require_tx_power_support

  ensure_nv "$NR5G_NV" "$NR5G_2X2" "nr5g 4x4"
  ensure_nv "$LTE_NV" "$LTE_NO_4X4" "lte 4x4"

  if [ "$variant" = NA ]; then
    ensure_tx_power
  else
    log "tx power: left at the default (EM)"
  fi

  if [ "$CHANGED" -eq 1 ]; then
    log "NV written -- a reset is needed before it takes effect"
    exit 10
  fi
  log "already configured, nothing written"
  exit 0
}

main "$@"
