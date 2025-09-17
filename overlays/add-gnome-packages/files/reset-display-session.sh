#!/bin/bash

set -euo pipefail

echo "Cleaning up display and session configuration..."

# Remove user-specific files
rm -f "/home/particle/.config/.fixup_displays_done"
rm -f "/home/particle/.config/monitors.xml"
rm -f "/home/particle/.cache/monitors.xml"

# Remove saved session if it exists
if [ -d "/home/particle/.config/gnome-session/saved-session" ]; then
    rm -f "/home/particle/.config/gnome-session/saved-session"/*
fi

# Remove from /etc/skel so future users don’t inherit stale configs
rm -f /etc/skel/.config/.fixup_displays_done || true
rm -f /etc/skel/.config/monitors.xml || true

echo "Display state reset complete."