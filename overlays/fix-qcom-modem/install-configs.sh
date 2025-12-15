#!/bin/bash
set -euo pipefail

# Create ModemManager config directory and install filter config
mkdir -p /etc/ModemManager/conf.d
cat > /etc/ModemManager/conf.d/99-tachyon-ignore-at.conf << 'EOF'
[Filter]
IgnoreDevice=tty:wwan0at0
IgnoreDevice=tty:wwan0at1
EOF

# Install udev rules for wwan interface
mkdir -p /etc/udev/rules.d
cat > /etc/udev/rules.d/99-tachyon-wwan.rules << 'EOF'
# 1) Mark rmnet_ipa0 as a ModemManager candidate for the qcom-soc plugin
ACTION=="add|change", \
  SUBSYSTEM=="net", \
  NAME=="rmnet_ipa0", \
  ENV{ID_MM_CANDIDATE}="1", \
  ENV{ID_MM_QCOM_SOC}="1"

# 2) Explicitly ignore the broken AT-style wwan ports
ACTION=="add|change", \
  KERNEL=="wwan0at*", \
  ENV{ID_MM_PORT_IGNORE}="1"
EOF

echo "ModemManager and udev configs installed successfully"
