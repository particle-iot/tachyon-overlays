#!/bin/bash
# Install Chromium from the snap store, once, on first boot.
#
# Ubuntu 24.04 ships no chromium deb -- the archive package is a transitional
# stub that pulls the snap -- and the 20.04 overlay's PPA
# (ppa:saiarcot895/chromium-beta) has no noble build at all
# (dists/noble/Release is HTTP 404). So the snap is the only route.
#
# This cannot be done at image-build time: snapd is not running inside the
# build chroot, so `snap install` fails there. Seeding the snap by hand into
# /var/lib/snapd/seed would bake it in, but a malformed seed breaks first boot,
# and nothing else in this repo seeds snaps. Installing on first boot keeps the
# failure mode contained: if it does not work, the desktop still comes up.
set -uo pipefail

STAMP=/var/lib/tachyon/chromium-snap.done
mkdir -p "$(dirname "$STAMP")"

if [ -e "$STAMP" ]; then
    echo "chromium snap already handled ($STAMP present); nothing to do"
    exit 0
fi

if snap list chromium >/dev/null 2>&1; then
    echo "chromium snap already installed"
    touch "$STAMP"
    exit 0
fi

# The store needs working DNS + egress. Retry rather than failing the boot on a
# slow network coming up.
for attempt in 1 2 3 4 5; do
    if snap install chromium; then
        echo "chromium snap installed on attempt ${attempt}"
        touch "$STAMP"
        exit 0
    fi
    echo "snap install chromium failed (attempt ${attempt}/5); retrying in 30s" >&2
    sleep 30
done

echo "ERROR: could not install the chromium snap after 5 attempts; leaving unstamped so the next boot retries" >&2
exit 1
