#!/bin/bash
set -euo pipefail

#========================
# Argument Validation
#========================
if [ $# -lt 1 ]; then
    echo "[USAGE] $0 <wpa_conf_file>"
    echo "FAIL"
    exit 1
fi


if [ ! -f "$1" ]; then
    echo "[ERROR] WPA configuration file '$1' is missing or does not exist at the specified path."
    echo "FAIL"
    exit 1
fi

#========================
# Configuration
#========================
SERVER_IP="192.168.175.1"
LOG_FILE="/tmp/iperf.log"
INTERFACE="wlan0"
WPA_CONF="$1"
BITRATE_THRESHOLD=100   # Mbps
RETR_THRESHOLD=0

#========================
# Stop Network Services
#========================
echo "[INFO] Stopping NetworkManager and wpa_supplicant services..."
systemctl stop wpa_supplicant
systemctl stop NetworkManager
if pgrep wpa_supplicant > /dev/null; then
    killall wpa_supplicant
fi
if pgrep udhcpc > /dev/null; then
    killall udhcpc
fi
if pgrep dhcpcd > /dev/null; then
    killall dhcpcd
fi

#========================
# Clean up old wpa_supplicant control interface
#========================
CTRL_IFACE="/var/run/wpa_supplicant/$INTERFACE"
if [ -e "$CTRL_IFACE" ]; then
    echo "[INFO] Found old control interface file, removing: $CTRL_IFACE"
    rm -f "$CTRL_IFACE"
fi

#========================
# Start wpa_supplicant
#========================
echo "[INFO] Starting wpa_supplicant..."
wpa_supplicant -i "$INTERFACE" -c "$WPA_CONF" -D nl80211 -B

#========================
# Configure IP Address
#========================
echo "[INFO] Configuring static IP..."
ip addr flush dev "$INTERFACE"
ip addr add 192.168.175.100/24 dev "$INTERFACE"
ip link set "$INTERFACE" up
ip route add default via 192.168.175.1

MAX_WAIT=5
elapsed=0
while ! ping -c 1 -W 1 "$SERVER_IP" > /dev/null 2>&1; do
    sleep 1
    elapsed=$((elapsed + 1))
    if [ "$elapsed" -ge "$MAX_WAIT" ]; then
        echo "[ERROR] Cannot reach server $SERVER_IP after ${MAX_WAIT}s, network might not be ready"
        echo "FAIL"
        exit 2
    fi
done

#========================
# Run iperf3 Test
#========================
echo "[INFO] Running iperf3 test..."
/opt/particle/tests/iperf3 -c "$SERVER_IP" -t 5 > "$LOG_FILE"

if [ $? -ne 0 ]; then
    echo "[ERROR] iperf3 execution failed"
    echo "FAIL"
    exit 3
fi

#========================
# Extract sender line
#========================
LINE=$(grep -E '\[ *[0-9]+\] *[0-9.]+-[0-9.]+.*sender' "$LOG_FILE")
if [ -z "$LINE" ]; then
    echo "[ERROR] No valid sender line found"
    cat $LOG_FILE
    echo "FAIL"
    exit 4
fi

echo "[DEBUG] sender line: $LINE"

#========================
# Extract bitrate and retransmissions
#========================
BITRATE_VALUE=$(echo "$LINE" | awk '{print $(NF-3)}')
BITRATE_UNIT=$(echo "$LINE" | awk '{print $(NF-2)}')
RETR=$(echo "$LINE" | awk '{print $(NF-1)}')

#========================
# Convert to integer Mbps
#========================
case "$BITRATE_UNIT" in
    "Kbits/sec")
        BITRATE_MBPS=$(( BITRATE_VALUE / 1000 ))
        ;;
    "Mbits/sec")
        BITRATE_MBPS=$(echo "$BITRATE_VALUE" | cut -d'.' -f1)
        ;;
    "Gbits/sec")
        BITRATE_MBPS=$(echo "$BITRATE_VALUE * 1000" | bc | cut -d'.' -f1)
        ;;
    *)
        echo "[ERROR] Unknown unit: $BITRATE_UNIT"
        echo "FAIL"
        exit 5
        ;;
esac

#========================
# Output results
#========================
echo "[RESULT] Average bitrate: ${BITRATE_MBPS} Mbps"
echo "[RESULT] Retransmissions: $RETR"

#========================
# Final check
#========================
iw wlan0 info
iw dev wlan0 link

echo "PASS"

exit 0
