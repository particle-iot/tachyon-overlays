#!/bin/bash
set -euo pipefail

bash <( curl -sL https://particle.io/install-cli )
# Add the udev rules
/root/bin/particle usb configure

# also install for particle user
su particle bash -c "bash <( curl -sL https://particle.io/install-cli )"
