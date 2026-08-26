#!/bin/bash
set -euo pipefail

# The 24.04 base image ships apt sources pinned to a single AWS region's Ubuntu
# ports mirror: tachyon-ubuntu-24.04 ci-scripts/build.sh sets
#
#     APT_MIRROR="http://us-east-1.ec2.ports.ubuntu.com/ubuntu-ports"
#
# and livecd-rootfs bakes that into sources.list via --mirror-chroot/--mirror-binary.
#
# On 2026-08-26 that mirror pool degraded and took down every tachyon-composer 24.04
# build. Measured directly against its six DNS backends:
#
#     44.201.142.251   HTTP 503 on 3/3 attempts (deterministic, 107-byte error body)
#     the other five   1 MiB in 4.8s - 15.2s, i.e. 65-210 KB/s
#     sustained 4 MiB  503 at 259 B/s, against 1,186,570 B/s from ports.ubuntu.com
#
# ~4500x slower, with one backend in six a hard 503. The chroot needs ~196 MB, so
# `apt-get upgrade` could not finish; small index files still slipped through, which
# is why `apt-get update` succeeded and only the pool downloads failed. The same build
# job proved the hostname was the whole story: its Docker builder image, on
# ports.ubuntu.com, completed fine in the same minute from the same egress IP.
#
# So: use the generic mirror inside the chroot. Rewrite only the host, keeping the
# /ubuntu-ports path, the suites and the components exactly as the base set them.
#
# This is a workaround at the wrong layer -- the durable fix is APT_MIRROR in
# tachyon-ubuntu-24.04, which also stops shipped devices from doing apt against a
# us-east-1 mirror. Drop this overlay once the base image no longer region-pins.

# ERE (sed -E) so the expression is not GNU-only: ? and + mean the same on BSD sed.
OLD_RE='https?://[a-z0-9-]+\.ec2\.ports\.ubuntu\.com'
NEW='http://ports.ubuntu.com'

echo "[use-generic-ubuntu-mirror] apt sources before:"
grep -rhoE 'https?://[^ ]*ports\.ubuntu\.com[^ ]*' \
  /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null | sort -u | sed 's/^/    /' || true

changed=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  if grep -q 'ec2\.ports\.ubuntu\.com' "$f"; then
    sed -E -i "s|${OLD_RE}|${NEW}|g" "$f"
    echo "[use-generic-ubuntu-mirror] rewrote ${f}"
    changed=$((changed + 1))
  fi
done <<EOF
/etc/apt/sources.list
$(find /etc/apt/sources.list.d -type f \( -name '*.list' -o -name '*.sources' \) 2>/dev/null || true)
EOF

if [ "$changed" -eq 0 ]; then
  # Not an error: a rebuilt base that no longer region-pins lands here, and so does a
  # second run of this overlay. Only worth saying out loud.
  echo "[use-generic-ubuntu-mirror] nothing to change; no ec2.ports.ubuntu.com sources found"
else
  echo "[use-generic-ubuntu-mirror] updated ${changed} file(s)"
fi

# Fail loudly rather than proceed to apt with a source we know is broken.
if grep -rq 'ec2\.ports\.ubuntu\.com' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
  echo "[use-generic-ubuntu-mirror] ERROR: ec2.ports.ubuntu.com still present after rewrite" >&2
  grep -rn 'ec2\.ports\.ubuntu\.com' /etc/apt/sources.list /etc/apt/sources.list.d/ >&2 || true
  exit 1
fi

echo "[use-generic-ubuntu-mirror] apt sources after:"
grep -rhoE 'https?://[^ ]*ports\.ubuntu\.com[^ ]*' \
  /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null | sort -u | sed 's/^/    /' || true
