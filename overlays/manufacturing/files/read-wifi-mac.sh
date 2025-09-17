#!/bin/bash
set -uo pipefail

# Print PASS on success or FAIL on error
trap 'rc=$?; if [ $rc -ne 0 ]; then echo "FAIL"; else echo "PASS"; fi' EXIT

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AT_RESULT=$("$DIR/send-at-command.sh" at+qnvr=4678,0)
AT_RC=$?

if [ $AT_RC -ne 0 ]; then
  echo "$AT_RESULT"
  exit $AT_RC
fi

set -e

MAC_ADDR=$(awk -F'"' '/QNVR/ {print $2}' <<<"$AT_RESULT" | grep -E '^[0-9A-Fa-f]{12}$')
FORMATTED=$(echo "$MAC_ADDR" | sed 's/../&:/g; s/:$//' | tr '[:upper:]' '[:lower:]')

echo "wifi_mac = $FORMATTED"
