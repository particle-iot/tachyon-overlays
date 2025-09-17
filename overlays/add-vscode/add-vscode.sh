#!/bin/bash
set -euo pipefail

# Download and install Microsoft signing key
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/packages.microsoft.gpg
sudo install -D -m 644 /tmp/packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg

# Add VS Code repository
echo "deb [arch=arm64 signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null

# Clean up temporary file
rm -f /tmp/packages.microsoft.gpg

# Update package lists and install VS Code
sudo apt update
sudo apt install code -y

# Preinstall Workbench extension for the particle user
sudo -u particle code --install-extension Particle.Particle-VSCode-Pack
