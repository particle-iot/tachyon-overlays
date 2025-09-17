#!/bin/bash

echo "Running chroot setup for test-overlay..."
echo "Installing nano and curl in the chroot environment..."
apt-get update && apt-get install -y nano curl
echo "Creating a file to copy back to the host..."
echo "This file will be copied back to the host!" > /tmp/test-overlay/chroot-copy-back.txt
echo "Chroot setup complete."
