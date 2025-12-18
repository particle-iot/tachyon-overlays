#!/bin/bash
set -euo pipefail

echo "Installing SSH server..."
apt-get update
apt-get install -y openssh-server

echo "Modifying /etc/ssh/sshd_config..."
# Update Port and ListenAddress in the configuration file
sed -i 's/^#Port 22/Port 22/' /etc/ssh/sshd_config
sed -i 's/^ListenAddress.*/ListenAddress 0.0.0.0/' /etc/ssh/sshd_config

# Enable root login (uncomment and change existing line)
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config

# Enable password authentication (add if not present, otherwise replace)
if grep -q "^#*PasswordAuthentication" /etc/ssh/sshd_config; then
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
else
    echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
fi

echo "Removing existing host keys, they will be generated uniquely on boot..."
rm -f /etc/ssh/ssh_host_*

echo "SSH setup and configuration complete."
