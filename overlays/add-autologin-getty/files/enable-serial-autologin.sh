#!/usr/bin/env bash
set -euo pipefail

TTY="ttyMSM0"

echo "serial-autologin: enabling autologin on $TTY"

# Ensure PAM securetty permits root on this TTY (if file exists)
if [[ -f /etc/securetty ]] && ! grep -qx "$TTY" /etc/securetty; then
  echo "$TTY" >> /etc/securetty
fi

# Create a systemd drop-in for this instance
DIR="/etc/systemd/system/getty@${TTY}.service.d"
mkdir -p "$DIR"
cat > "${DIR}/override.conf" <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear --keep-baud 115200,38400,9600 %I $TERM
EOF

# Enable and restart the instance
systemctl daemon-reload
systemctl enable "getty@${TTY}.service" >/dev/null 2>&1 || true
systemctl restart "getty@${TTY}.service" || true