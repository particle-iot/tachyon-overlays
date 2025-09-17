#!/bin/bash

CPUSET_VERSION="1.0.0"

# Check if an argument is provided
if [ -z "$1" ]; then
  echo "No option provided. Use 'help' for more information."
  exit 1
fi

# Main case statement to handle the provided argument
case "$1" in
  "min")
    # Minimal CPU governance
    MODE=powersave
    ;;
  
  "full")
    # Full CPU governance
    MODE=performance
    ;;
  
  "version")
    # Show version and exit
    echo "cpuset.sh" $CPUSET_VERSION
    exit 0
    ;;

  "help")
    # Show help and exit
    echo "Usage: cpuset.sh [option]"
    echo "Options:"
    echo "  min      - Minimal CPU governance"
    echo "  full     - Full CPU governance"
    echo "  version  - Display the version number"
    echo "  help     - Display this help message"
    exit 0
    ;;
  
  *)
    echo "Invalid option. Use 'help' for more information."
    exit 1
    ;;
esac

# Can be consolidated with for loop.  For now, keep as separate writes
echo $MODE > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
echo $MODE > /sys/devices/system/cpu/cpu1/cpufreq/scaling_governor
echo $MODE > /sys/devices/system/cpu/cpu2/cpufreq/scaling_governor
echo $MODE > /sys/devices/system/cpu/cpu3/cpufreq/scaling_governor
echo $MODE > /sys/devices/system/cpu/cpu4/cpufreq/scaling_governor
echo $MODE > /sys/devices/system/cpu/cpu5/cpufreq/scaling_governor
echo $MODE > /sys/devices/system/cpu/cpu6/cpufreq/scaling_governor
echo $MODE > /sys/devices/system/cpu/cpu7/cpufreq/scaling_governor
exit 0