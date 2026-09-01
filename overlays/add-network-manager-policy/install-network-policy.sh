#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt update -y

# The legacy polkit .pkla backend (polkitd-pkla) and policykit-desktop-privileges
# were dropped in 26.04/resolute, which uses polkit JS .rules exclusively. Install
# whichever this release still ships -- so 24.04's .pkla path keeps working -- and
# skip the rest. The .rules file this overlay also installs is what enforces the
# policy on 26.04 (and harmlessly duplicates it on 24.04).
for p in polkitd-pkla policykit-desktop-privileges; do
  if apt-cache show "${p}" >/dev/null 2>&1; then
    apt install -y "${p}"
  else
    echo "skipping package not available in this release: ${p}"
  fi
done

# Ensure both policy directories exist: the mandatory .pkla dir (24.04) and the
# JS .rules dir (all releases).
mkdir -p /etc/polkit-1/localauthority/90-mandatory.d /etc/polkit-1/rules.d
