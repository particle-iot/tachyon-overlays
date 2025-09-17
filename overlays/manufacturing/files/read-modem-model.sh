#!/bin/bash
set -uo pipefail

# Print PASS on success or FAIL on error
trap 'rc=$?; if [ $rc -ne 0 ]; then echo "FAIL"; else echo "PASS"; fi' EXIT

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AT_RESULT=$("$DIR/send-at-command.sh" at+gmm)
AT_RC=$?

if [ $AT_RC -ne 0 ]; then
  echo "$AT_RESULT"
  exit $AT_RC
fi

set -e

CLEANED=$(echo "$AT_RESULT" \
            | sed 's/[^[:print:]]//g' \
            | grep -v '^[[:space:]]*$' \
            | head -n 1 \
            | grep -v '^OK$' \
            | grep -v '^PASS$')

echo "modem_model = $CLEANED"
