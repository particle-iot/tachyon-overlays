#!/bin/bash
set -euo pipefail

sudo apt-get install lshw jq expect -y

# GNSS needs a lib
cd /opt/particle/tests
npm install nmea-simple --no-save
