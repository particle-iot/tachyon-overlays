#!/bin/bash
set -euo pipefail

# Make a dummy `bluez` library with dependencies already met by prebuilt bluez5
# echo "Building dummy bluez package"
# if equivs-build /tmp/bluez; then
#   echo "Built dummy bluez package."
# else
#   echo "Failed to build dummy bluez package."
#   exit 1
# fi

echo "Installing dummy bluez package"
if dpkg -i /tmp/bluez_5.56_all.deb; then
  echo "Installed dummy bluez package."
else
  echo "Failed to install dummy bluez package."
  exit 1
fi

# Add in minimal install packages for bluetooth audio, this should use the dummy `bluez` package and not attempt to install upstream `bluez`
# Has the following dependencies
# Depends: libc6 (>= 2.17), libdbus-1-3 (>= 1.9.14), libpulse0 (= 1:13.99.1-1ubuntu3.13), libsbc1, pulseaudio (= 1:13.99.1-1ubuntu3.13), bluez (>= 5.23)
if apt-get install -y pulseaudio-module-bluetooth pavucontrol blueman; then
  echo "Bluetooth packages installed successfully."
else
  echo "Error installing bluetooth packages."
  exit 1
fi

# Ensure needed pulse audio bluetooth modules are loaded
# echo "Pulse config files before modification"
# ls -la /etc/pulse/
# cat /etc/pulse/default.pa

sudo tee -a /etc/pulse/default.pa > /dev/null << 'EOF'

.ifexists module-bluetooth-policy.so
load-module module-bluetooth-policy
.endif

.ifexists module-bluetooth-discover.so
load-module module-bluetooth-discover
.endif

.ifexists module-bluez5-discover.so
load-module module-bluez5-discover
.endif

.ifexists module-dbus-protocol.so
load-module module-dbus-protocol
.endif
EOF

# echo "Pulse config files after modification"
# cat /etc/pulse/default.pa

#rm /tmp/bluez
rm ./tmp/bluez_5.56_all.deb
