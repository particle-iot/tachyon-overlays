#!/bin/bash
set -euo pipefail

# Print PASS on success or FAIL on error
trap 'rc=$?; if [ $rc -ne 0 ]; then echo "FAIL"; else echo "PASS"; fi' EXIT

DISTRO_FILE="/etc/particle/distro_versions.json"

if [[ ! -f "$DISTRO_FILE" ]]; then
    echo "Error: $DISTRO_FILE does not exist"
    exit 1
fi

# Validate and minify the JSON
if ! jq -e . "$DISTRO_FILE" > /dev/null 2>&1; then
    echo "Error: $DISTRO_FILE is not a valid JSON file"
    exit 1
fi

MINIFIED_JSON=$(jq -c . "$DISTRO_FILE")
echo "distro_versions = $MINIFIED_JSON"
