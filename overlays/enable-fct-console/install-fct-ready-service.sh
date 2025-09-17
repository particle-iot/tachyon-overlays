#!/bin/bash
set -euo pipefail

SERVICE_NAME="fct-ready.service"
SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME"

echo "Installing $SERVICE_NAME..."

cat <<EOF | sudo tee "$SERVICE_PATH" > /dev/null
[Unit]
Description=Emit FCT ready signal
After=serial-getty@ttyMSM0.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'sleep 7; echo "[FCT_READY]" > /dev/ttyMSM0'

[Install]
WantedBy=ffbm.target
EOF

echo "Reloading systemd..."
sudo systemctl daemon-reexec

echo "Enabling service for ffbm.target..."
sudo systemctl enable "$SERVICE_NAME"

echo "Done. $SERVICE_NAME is now set to run only under ffbm.target."
