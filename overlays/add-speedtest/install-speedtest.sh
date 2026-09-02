#!/bin/bash
set -euo pipefail

# Ookla's packagecloud repo is keyed by Ubuntu codename; if it has no 'resolute'
# (26.04) distribution yet, the repo setup or the install fails. speedtest is a
# non-critical convenience tool, so warn and continue rather than sink the build.
if curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | sudo bash; then
  sudo apt-get install -y speedtest || echo "speedtest package unavailable for this release; skipping"
else
  echo "Ookla speedtest repo not available for this release; skipping speedtest"
fi
