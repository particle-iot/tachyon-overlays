#!/bin/bash
set -euo pipefail

CONFIG_FILE="/etc/gdm3/custom.conf"
TMP_FILE=$(mktemp)

# Ensure the file exists and is writable
if [[ ! -f "$CONFIG_FILE" || ! -w "$CONFIG_FILE" ]]; then
    echo "Error: Cannot access $CONFIG_FILE"
    exit 1
fi

# Use sed to uncomment and replace target lines
sed -E \
  -e 's/^[[:space:]]*#[[:space:]]*AutomaticLoginEnable[[:space:]]*=[[:space:]]*true/AutomaticLoginEnable = true/' \
  -e 's/^[[:space:]]*#[[:space:]]*AutomaticLogin[[:space:]]*=[[:space:]]*user1/AutomaticLogin = particle/' \
  "$CONFIG_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$CONFIG_FILE"

chmod a+r $CONFIG_FILE
