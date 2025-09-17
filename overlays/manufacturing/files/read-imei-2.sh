#!/bin/bash
set -uo pipefail

# Print PASS on success or FAIL on error
trap 'rc=$?; if [ $rc -ne 0 ]; then echo "FAIL"; else echo "PASS"; fi' EXIT

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AT_RESULT=$("$DIR/send-at-command.sh" at+egmr=0,10)
AT_RC=$?

if [ $AT_RC -ne 0 ]; then
  echo "$AT_RESULT"
  exit $AT_RC
fi

set -e

CLEANED=$(awk -F'"' '/EGMR/ {print $2}' <<<"$AT_RESULT")

echo "imei_2 = $CLEANED"
