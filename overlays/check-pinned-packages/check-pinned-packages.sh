#!/bin/bash
set -euo pipefail

echo "[check-pinned-packages] Checking pinned package versions can be satisfied"

# Track packages to install
PACKAGES_TO_INSTALL_APT=()
PACKAGES_TO_INSTALL_URL=()

# Loop through all environment variables looking for PKG_* pattern
for var in $(compgen -e | grep '^PKG_'); do
  # Skip metadata variables (not actual packages)
  if [[ "$var" =~ ^PKG_DISTRO_ ]] || [[ "$var" =~ ^PKG_SRC_ ]]; then
    continue
  fi

  # Skip _URL variables - they're companions to the version variables
  case "$var" in
    *_URL) continue ;;
  esac

  # Get the value
  value="${!var}"

  # Only process variables starting with PKG_ and having alphanumeric names (but not ending in _URL)
  if [[ "$var" =~ ^PKG_[A-Za-z0-9_]+$ ]] && [[ ! "$var" =~ _URL$ ]] && [ -n "$value" ]; then
    # Convert PKG_foo_bar to foo-bar package name
    pkg_name="${var#PKG_}"              # Remove PKG_ prefix
    pkg_name="${pkg_name//_/-}"         # Replace _ with -
    pkg_name=$(echo "$pkg_name" | tr '[:upper:]' '[:lower:]')  # Convert to lowercase

    # Check if there's a companion _URL variable
    url_var="${var}_URL"
    if [ -n "${!url_var:-}" ]; then
      echo "  → Will install ${pkg_name} (version ${value}) from URL: ${!url_var}"
      PACKAGES_TO_INSTALL_URL+=("${pkg_name}|${!url_var}|${value}")
    else
      echo "  → Will install ${pkg_name}=${value}"
      PACKAGES_TO_INSTALL_APT+=("${pkg_name}=${value}")
    fi
  fi
done

# Install packages from URLs (download and dpkg -i)
if [ ${#PACKAGES_TO_INSTALL_URL[@]} -gt 0 ]; then
  echo "[check-pinned-packages] Installing ${#PACKAGES_TO_INSTALL_URL[@]} package(s) from URL:"

  for entry in "${PACKAGES_TO_INSTALL_URL[@]}"; do
    IFS='|' read -r pkg_name url expected_version <<< "$entry"
    deb_file="/tmp/${pkg_name}.deb"

    echo "  → Downloading ${pkg_name} (expecting version ${expected_version}) from ${url}"
    if ! curl -fL --retry 3 -o "${deb_file}" "${url}"; then
      echo "" >&2
      echo "========================================================================" >&2
      echo "[check-pinned-packages] ✗ ERROR: Failed to download ${pkg_name}" >&2
      echo "URL: ${url}" >&2
      echo "========================================================================" >&2
      exit 1
    fi

    echo "  → Installing ${pkg_name} via dpkg"
    if ! dpkg -i "${deb_file}"; then
      echo "  → Fixing dependencies with apt-get -f install"
      apt-get install -f -y
    fi

    rm -f "${deb_file}"
    echo "  ✓ Installed ${pkg_name} from URL"
  done
fi

# Install packages via APT
if [ ${#PACKAGES_TO_INSTALL_APT[@]} -gt 0 ]; then
  echo "[check-pinned-packages] Installing ${#PACKAGES_TO_INSTALL_APT[@]} pinned package(s) via APT:"

  # Explicitly install packages and check for failure
  if ! apt-get install -y --allow-downgrades "${PACKAGES_TO_INSTALL_APT[@]}"; then
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

  echo "[check-pinned-packages] ✓ All APT packages installed successfully"
fi

if [ ${#PACKAGES_TO_INSTALL_URL[@]} -eq 0 ] && [ ${#PACKAGES_TO_INSTALL_APT[@]} -eq 0 ]; then
  echo "[check-pinned-packages] No PKG_* environment variables found"
fi

echo "[check-pinned-packages] ✓ All pinned packages installed successfully"
exit 0
