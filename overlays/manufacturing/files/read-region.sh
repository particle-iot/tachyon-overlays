#!/bin/bash
set -uo pipefail

# Print PASS on success or FAIL on error
trap 'rc=$?; if [ $rc -ne 0 ]; then echo "FAIL"; else echo "PASS"; fi' EXIT

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AT_RESULT=$("$DIR/send-at-command.sh" at+gmr)
AT_RC=$?

if [ $AT_RC -ne 0 ]; then
  echo "$AT_RESULT"
  exit $AT_RC
fi

FIRMWARE_LINE=$(echo "$AT_RESULT" \ | grep -E '^SG560D'  | head -n1)

if [[ -z "$FIRMWARE_LINE" ]]; then
    echo "Error: firmware line not found in AT output"
    echo "$AT_RESULT"
    exit 1
fi

set -e

REGION_SUBSTR=${FIRMWARE_LINE:6:2}

case "$REGION_SUBSTR" in
    NA) OUTPUT="NA" ;;
    EM) OUTPUT="RoW" ;;
    *)
        echo "Error: region must be NA or RoW, got $REGION_SUBSTR"
        exit 1
        ;;
esac

echo "region = $OUTPUT"
