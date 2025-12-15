#!/bin/bash
set -euo pipefail

# Create systemd service override directories
mkdir -p /etc/systemd/system/ModemManager.service.d
mkdir -p /etc/systemd/system/rmtfs.service.d

# Install ModemManager service override
cat > /etc/systemd/system/ModemManager.service.d/override.conf << 'EOF'
[Unit]
# Ensure rmtfs is up before ModemManager starts
After=rmtfs.service
Requires=rmtfs.service

[Service]
RestrictAddressFamilies=
RestrictAddressFamilies=AF_NETLINK AF_UNIX AF_QIPCRTR AF_INET AF_INET6
Environment=MM_PLUGIN_DEBUG=qcom-soc
# Add a delay to ensure the modem has initialized and QRTR is populated
ExecStartPre=/bin/sleep 10
ExecStart=
ExecStart=/usr/sbin/ModemManager --debug
EOF

# Install rmtfs service override
cat > /etc/systemd/system/rmtfs.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/rmtfs -P -o /persist/rmtfs -s -v
EOF

echo "Systemd service overrides installed successfully"
