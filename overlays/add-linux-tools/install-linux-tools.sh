#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt update -y

# linux-tools-qcom belongs to the qcom kernel flavour, which 26.04/resolute does
# not ship (there is no linux-qcom for resolute). Install whatever this release
# offers and skip the rest, so the missing qcom tools can't sink the build.
# (cpupower via the qcom tools is thus 24.04-only for now; tracked as a follow-up.)
avail=""
for p in linux-tools-qcom lm-sensors; do
  if apt-cache show "${p}" >/dev/null 2>&1; then
    avail="${avail} ${p}"
  else
    echo "skipping package not available in this release: ${p}"
  fi
done
if [ -n "${avail}" ]; then
  apt install -y ${avail}
fi
