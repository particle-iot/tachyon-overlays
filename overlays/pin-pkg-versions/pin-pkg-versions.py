#!/usr/bin/env python3
import os
import re
import sys
from pathlib import Path

DEST = Path("/etc/apt/preferences.d/build-pins.pref")
DEFAULT_PIN_PRIORITY = 1000
PKG_ENV_PATTERN = re.compile(r"^PKG_[A-Za-z0-9_]+$")

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