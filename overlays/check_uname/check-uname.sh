#!/bin/bash

echo "Checking system architecture..."

ARCH=$(uname -m)

if [ "$ARCH" == "aarch64" ]; then
  echo "Architecture is arm64 (aarch64)."
  exit 0
else
  echo "Error: Expected architecture is arm64 (aarch64), but found $ARCH."
  exit 1
fi


#check that the version of ubuntu is in the environment variable UBUNTU_VERSION and the same as source /etc/os-release; echo "$VERSION_ID"
if [ -z "$UBUNTU_VERSION" ]; then
  echo "Error: UBUNTU_VERSION environment variable is not set."
  exit 1
fi

if [ "$UBUNTU_VERSION" != "$(source /etc/os-release && echo "$VERSION_ID")" ]; then
  echo "Error: UBUNTU_VERSION ($UBUNTU_VERSION) does not match /etc/os-release ($VERSION_ID)."
  exit 1
fi
echo "Ubuntu version is $UBUNTU_VERSION."
echo "System architecture and version check passed."

