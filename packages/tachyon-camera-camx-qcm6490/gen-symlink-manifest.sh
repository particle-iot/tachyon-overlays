#!/bin/bash
# Regenerate the /usr/lib symlink manifest from a live, working device.
#
# The CamX debs install their shared objects under /usr/lib/qcm6490/ but the
# binaries look for them on the default search path, so each one needs a link
# in /usr/lib. Rather than globbing *.so* at install time - which would
# silently overwrite whatever happens to sit at those paths - the link set is
# captured here once, reviewed, and shipped as package payload.
#
# Usage: ./gen-symlink-manifest.sh root@192.168.31.24 [output]
set -euo pipefail

host=${1:?usage: $0 <user@host> [output]}
out=${2:-manifest/usr-lib-symlinks.txt}
mkdir -p "$(dirname "$out")"

# shellcheck disable=SC2029  # remote expansion is intended
ssh "$host" 'ls -1 /usr/lib/qcm6490/*.so* 2>/dev/null' \
    | sed 's#.*/##' | sort -u > /tmp/.camx-sos.$$

{
    echo "# /usr/lib symlinks required by the CamX stack"
    echo "# generated from $host on $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "# format: <link path> <target>"
    while read -r so; do
        [ -n "$so" ] || continue
        echo "/usr/lib/$so /usr/lib/qcm6490/$so"
    done < /tmp/.camx-sos.$$
} > "$out"

rm -f /tmp/.camx-sos.$$
echo "wrote $out ($(grep -vc '^#' "$out") links)"
