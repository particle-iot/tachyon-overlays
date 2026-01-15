#!/bin/bash
set -euo pipefail

echo "[check-pinned-packages] Version 2025-01-15-v5 with multi-URL support (<;> delimiter)"
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
  # Debug: show what we're checking
  var_suffix="${var: -4}"
  if [ "$var_suffix" = "_URL" ]; then
    echo "  [DEBUG] Skipping URL variable: $var"
    continue
  fi

  # Get the value
  value="${!var}"

  # Only process variables starting with PKG_ and having alphanumeric names
  if [[ "$var" =~ ^PKG_[A-Za-z0-9_]+$ ]] && [ -n "$value" ]; then
    # Convert PKG_foo_bar to foo-bar package name
    pkg_name="${var#PKG_}"              # Remove PKG_ prefix
    pkg_name="${pkg_name//_/-}"         # Replace _ with -
    pkg_name=$(echo "$pkg_name" | tr '[:upper:]' '[:lower:]')  # Convert to lowercase

    # Check if there's a companion _URL variable
    url_var="${var}_URL"
    if [ -n "${!url_var:-}" ]; then
      echo "  → Will install ${pkg_name} (version ${value}) from URL: ${!url_var}"
      # Use tab as field separator (won't appear in URLs or package names)
      PACKAGES_TO_INSTALL_URL+=("${pkg_name}"$'\t'"${!url_var}"$'\t'"${value}")
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
    # Use tab as field separator (matches storage format)
    IFS=$'\t' read -r pkg_name urls expected_version <<< "$entry"

    # Split URLs on <;> delimiter to support multiple .deb files (e.g., kernel image + modules)
    # Note: Can't use IFS with multi-char delimiter, so manually split on <;>
    IFS='~' read -ra URL_ARRAY <<< "${urls//<;>/~}"

    echo "  → Package: ${pkg_name} (version ${expected_version})"
    echo "  → Found ${#URL_ARRAY[@]} file(s) to download"

    # Download all files
    deb_files=()
    for i in "${!URL_ARRAY[@]}"; do
      url="${URL_ARRAY[$i]}"
      deb_file="/tmp/${pkg_name}-${i}.deb"
      deb_files+=("${deb_file}")

      echo "    → Downloading file $((i+1))/${#URL_ARRAY[@]}: ${url}"
      if ! curl -fL --retry 3 -o "${deb_file}" "${url}"; then
        echo "" >&2
        echo "========================================================================" >&2
        echo "[check-pinned-packages] ✗ ERROR: Failed to download ${pkg_name}" >&2
        echo "URL: ${url}" >&2
        echo "========================================================================" >&2
        exit 1
      fi
    done

    # Install all downloaded files together
    echo "  → Installing ${#deb_files[@]} package file(s) via dpkg"
    if ! dpkg -i "${deb_files[@]}"; then
      echo "  → Fixing dependencies with apt-get -f install"
      if ! apt-get install -f -y; then
        echo "" >&2
        echo "========================================================================" >&2
        echo "[check-pinned-packages] ✗ ERROR: Failed to install ${pkg_name}" >&2
        echo "The package was downloaded but dpkg installation failed" >&2
        echo "========================================================================" >&2
        exit 1
      fi
    fi

    # Clean up
    for deb_file in "${deb_files[@]}"; do
      rm -f "${deb_file}"
    done

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
