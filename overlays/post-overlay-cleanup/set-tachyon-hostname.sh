#!/bin/bash
set -euo pipefail

#the hostname is a "tachyon" + a random id that is like a commit id that is generated live
#this is to ensure that the hostname is unique and can be used to identify the device
HOSTNAME="tachyon-$(cat /proc/sys/kernel/random/uuid | cut -c 1-8)"

echo "Setting hostname to $HOSTNAME..." + $HOSTNAME

#the host file looks like this:
#127.0.0.1 localhost
#127.0.1.1 qcs6490-odk

#we want to replace qcs6490-odk
#with the hostname we generated

sed -i "s/qcs6490-odk/$HOSTNAME/g" /etc/hosts
