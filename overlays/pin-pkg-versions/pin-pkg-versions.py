#!/usr/bin/env python3
import os
import re
import sys
from pathlib import Path

DEST = Path("/etc/apt/preferences.d/build-pins.pref")
DEFAULT_PIN_PRIORITY = 1000
PKG_ENV_PATTERN = re.compile(r"^PKG_[A-Za-z0-9_]+$")

# Kernel upstream version + ABI, e.g. 6.8.0-1058.59+particle10 -> ("6.8.0", "1058")
KERNEL_ABI_PATTERN = re.compile(r"^(\d+\.\d+\.\d+)-(\d+)\.")

# The ABI-versioned kernel packages carry the ABI in their NAME
# (linux-image-6.8.0-1058-particle), so no PKG_<name> env var can ever
# address them: the PKG_ -> package mapping is lowercase + "_"->"-", which
# cannot produce dots.  They are also depended on WITHOUT a version:
#
#   linux-particle       Depends: linux-image-particle (= <ver>)      <- locked
#   linux-image-particle Depends: linux-image-<upstream>-<abi>-particle  <- unlocked
#
# so apt is free to leave a newer one in place.  Those two packages are the
# ones that actually contain vmlinuz and the modules, which is how an image
# can ship a DTB from one kernel build and a kernel from another.
KERNEL_ABI_STEMS = ("image", "modules", "headers")

def collect_pkg_env():
    """
    Collect env vars of the form PKG_<NAME>=<VERSION> and map to Debian
    package names:
      PKG_particle_linux=0.20.1-1  ->  ('particle-linux', '0.20.1-1')
    """
    pkgs = {}
    for k, v in os.environ.items():
        if not PKG_ENV_PATTERN.match(k):
            continue
        name = k[len("PKG_"):].replace("_", "-").lower().strip()
        ver  = v.strip()
        if name and ver:
            pkgs[name] = ver
    return pkgs

def expand_kernel_abi_pins(pkgs):
    """
    Given a pin on the linux-particle metapackage, also pin the ABI-versioned
    kernel packages it pulls in.  Their names are fully derivable from the
    pinned version, so this needs no extra configuration:

      6.8.0-1058.59+particle10 -> linux-image-6.8.0-1058-particle
                                  linux-modules-6.8.0-1058-particle
                                  linux-headers-6.8.0-1058-particle

    Without this the metapackages are held at the pinned version while
    vmlinuz and the modules float to whatever the archive last offered.
    No-ops on any version string that is not the kernel's scheme.
    """
    ver = pkgs.get("linux-particle")
    if not ver:
        return 0
    m = KERNEL_ABI_PATTERN.match(ver)
    if not m:
        return 0
    upstream, abi = m.group(1), m.group(2)
    added = 0
    for stem in KERNEL_ABI_STEMS:
        name = f"linux-{stem}-{upstream}-{abi}-particle"
        if name not in pkgs:
            pkgs[name] = ver
            added += 1
    return added

def get_priority():
    try:
        return int(os.environ.get("PIN_PRIORITY", DEFAULT_PIN_PRIORITY))
    except ValueError:
        return DEFAULT_PIN_PRIORITY

def generate_pin_content(packages, priority):
    lines = []
    for pkg, ver in packages.items():
        lines.append(f"Package: {pkg}")
        lines.append(f"Pin: version {ver}")
        lines.append(f"Pin-Priority: {priority}")
        lines.append("")  # blank line
    # trailing newline for POSIX tools
    return "\n".join(lines).rstrip() + "\n"

def main():
    pkgs = collect_pkg_env()
    n_kernel = expand_kernel_abi_pins(pkgs)
    if n_kernel:
        print(f"[pin-pkg-versions] Expanded {n_kernel} ABI-versioned kernel pin(s) "
              f"from linux-particle={pkgs['linux-particle']}", file=sys.stderr)
    if not pkgs:
        print("[pin-pkg-versions] No PKG_* env vars found; nothing to write.", file=sys.stderr)
        # still ensure the directory exists, but don't create an empty file
        DEST.parent.mkdir(parents=True, exist_ok=True)
        return 0

    #if the file exists already, exit successfully!
    if DEST.exists():
        print(f"[pin-pkg-versions] {DEST} already exists; not overwriting.", file=sys.stderr)
        return 0

    priority = get_priority()
    content = generate_pin_content(pkgs, priority)

    DEST.parent.mkdir(parents=True, exist_ok=True)
    tmp = DEST.with_suffix(".tmp")
    tmp.write_text(content, encoding="utf-8")
    os.chmod(tmp, 0o644)
    tmp.replace(DEST)

    print(f"[pin-pkg-versions] Wrote {len(pkgs)} pin(s) to {DEST} with priority {priority}:")
    for k, v in pkgs.items():
        print(f"  - {k} -> {v}")
    return 0

if __name__ == "__main__":
    sys.exit(main())