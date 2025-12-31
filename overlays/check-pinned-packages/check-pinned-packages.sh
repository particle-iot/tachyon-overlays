#!/bin/bash
set -euo pipefail

echo "[check-pinned-packages] Checking pinned package versions can be satisfied"

# Track packages to install
PACKAGES_TO_INSTALL=()

# Loop through all environment variables looking for PKG_* pattern
while IFS='=' read -r name value; do
  # Only process variables starting with PKG_
  if [[ "$name" =~ ^PKG_[A-Za-z0-9_]+$ ]]; then
    # Convert PKG_foo_bar to foo-bar package name
    pkg_name="${name#PKG_}"        # Remove PKG_ prefix
    pkg_name="${pkg_name//_/-}"    # Replace _ with -
    pkg_name="${pkg_name,,}"       # Convert to lowercase

    if [ -n "$value" ]; then
      echo "  → Will install ${pkg_name}=${value}"
      PACKAGES_TO_INSTALL+=("${pkg_name}=${value}")
    fi
  fi
done < <(env | grep '^PKG_')

# If we have packages to install, do it
if [ ${#PACKAGES_TO_INSTALL[@]} -gt 0 ]; then
  echo "[check-pinned-packages] Installing ${#PACKAGES_TO_INSTALL[@]} pinned package(s) (will fail if version not found):"

  # Explicitly install packages and check for failure
  if ! apt-get install -y --allow-downgrades "${PACKAGES_TO_INSTALL[@]}"; then
    echo "" >&2
    echo "========================================================================" >&2
    echo "[check-pinned-packages] ✗ ERROR: Failed to install pinned packages" >&2
    echo "========================================================================" >&2
    echo "One or more pinned package versions could not be found or installed." >&2
    echo "Check that the versions specified in versions.json are available in" >&2
    echo "the configured apt repositories." >&2
    echo "========================================================================" >&2
    exit 1
  fi

  echo "[check-pinned-packages] ✓ All pinned packages installed successfully"
else
  echo "[check-pinned-packages] No PKG_* environment variables found"
fi

exit 0
