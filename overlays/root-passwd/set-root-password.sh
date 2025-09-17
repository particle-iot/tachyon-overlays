#!/bin/bash
set -euo pipefail

NEW_PASSWORD=particle

echo "Setting root password in chroot..."

# Update the root password
echo "root:${NEW_PASSWORD}" | chpasswd

if [ $? -eq 0 ]; then
  echo "Root password successfully updated."
else
  echo "Failed to update root password."
  exit 1
fi
