#!/usr/bin/env python3
"""
JSON Builder for distro_versions.json

Reads version metadata from environment variables and generates
/etc/particle/distro_versions.json

Environment variables:
  DISTRO_VERSION, DISTRO_STACK, DISTRO_VARIANT, DISTRO_REGION, DISTRO_BOARD
  DISTRO_DISTRIBUTION, DISTRO_DISTRIBUTION_VERSION
  SRC_TACHYON_COMPOSER, SRC_UBUNTU_20_04, SRC_UBUNTU_24_04, SRC_U_BOOT, SRC_OVERLAYS

Usage:
    python3 json-builder.py [output_path]

If no output_path is provided, defaults to /etc/particle/distro_versions.json
"""

import json
import os
import sys
from pathlib import Path


DEFAULT_OUTPUT_PATH = Path("/etc/particle/distro_versions.json")


def collect_distro_metadata():
    """
    Collect DISTRO_* environment variables and build the distro section.
    """
    distro = {}

    # Map env var names to JSON keys
    distro_vars = {
        "DISTRO_VERSION": "version",
        "DISTRO_STACK": "stack",
        "DISTRO_VARIANT": "variant",
        "DISTRO_REGION": "region",
        "DISTRO_BOARD": "board",
        "DISTRO_DISTRIBUTION": "distribution",
        "DISTRO_DISTRIBUTION_VERSION": "distribution_version",
    }

    for env_key, json_key in distro_vars.items():
        value = os.environ.get(env_key, "").strip()
        if value:
            distro[json_key] = value

    return distro


def collect_source_metadata():
    """
    Collect SRC_* environment variables and build the src section.
    """
    src = {}

    # Map env var names to JSON keys
    src_vars = {
        "SRC_TACHYON_COMPOSER": "tachyon_composer",
        "SRC_UBUNTU_20_04": "ubuntu_20_04",
        "SRC_UBUNTU_24_04": "ubuntu_24_04",
        "SRC_U_BOOT": "u_boot",
        "SRC_OVERLAYS": "overlays",
    }

    for env_key, json_key in src_vars.items():
        value = os.environ.get(env_key, "").strip()
        if value:
            src[json_key] = value

    return src


def generate_version_metadata():
    """
    Generate the complete distro_versions.json structure.
    """
    metadata = {}

    distro = collect_distro_metadata()
    if distro:
        metadata["distro"] = distro

    src = collect_source_metadata()
    if src:
        metadata["src"] = src

    return metadata


def main():
    # Determine output path
    if len(sys.argv) > 1:
        output_path = Path(sys.argv[1])
    else:
        output_path = DEFAULT_OUTPUT_PATH

    # Collect metadata from environment
    metadata = generate_version_metadata()

    if not metadata:
        print("[json-builder] No DISTRO_* or SRC_* env vars found; creating empty metadata.", file=sys.stderr)

    # Ensure parent directory exists
    output_path.parent.mkdir(parents=True, exist_ok=True)

    # Write to temp file first, then rename (atomic)
    tmp_path = output_path.with_suffix(".tmp")
    with open(tmp_path, 'w') as f:
        json.dump(metadata, f, indent=2, sort_keys=True)
        f.write('\n')  # POSIX newline

    os.chmod(tmp_path, 0o644)
    tmp_path.replace(output_path)

    print(f"[json-builder] Wrote distro_versions.json to {output_path}")

    # output the JSON content as a nicely formatted string
    print("Generated metadata:")
    print(json.dumps(metadata, indent=2, sort_keys=True))

    if metadata.get("distro"):
        print(f"  Distro: {metadata['distro'].get('distribution', '?')} {metadata['distro'].get('distribution_version', '?')} v{metadata['distro'].get('version', '?')}")
    if metadata.get("src"):
        print(f"  Sources: {len(metadata['src'])} component(s)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
