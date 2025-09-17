#!/bin/bash
set -euo pipefail

ROOT_PART_PATH="/dev/disk/by-partlabel/system_a"
ALL_PASS=1  # Will set to 0 if any test fails

fail_test() {
  echo "FAIL: $1"
  ALL_PASS=0
}

pass_test() {
  echo "OK: $1"
}

# Test 1: Symlink check
if [[ -L "$ROOT_PART_PATH" ]]; then
  pass_test "Root partition path is a symlink"
else
  fail_test "Root partition path is not a symlink"
fi

# Test 2: Resolve symlink
if ROOT_PART_DEV=$(readlink -f "$ROOT_PART_PATH"); then
  pass_test "Symlink resolves to $ROOT_PART_DEV"
else
  fail_test "Failed to resolve symlink $ROOT_PART_PATH"
fi

# Test 3: Get root device name
if ROOT_DEVICE_NAME=$(lsblk -n -o PKNAME "$ROOT_PART_DEV"); then
  ROOT_DEVICE_PATH="/dev/${ROOT_DEVICE_NAME}"
  pass_test "Parent device identified as $ROOT_DEVICE_PATH"
else
  fail_test "Failed to get parent device for $ROOT_PART_DEV"
fi

# Test 4: Check root device is a disk
ROOT_DEVICE_TYPE=$(lsblk -nrdo TYPE "$ROOT_DEVICE_PATH")
if [[ "$ROOT_DEVICE_TYPE" == "disk" ]]; then
  pass_test "$ROOT_DEVICE_PATH is a disk"
else
  fail_test "$ROOT_DEVICE_PATH is not a disk (type: $ROOT_DEVICE_TYPE)"
fi

# Test 5: Check root partition is a partition
ROOT_PART_TYPE=$(lsblk -nrdo TYPE "$ROOT_PART_DEV")
if [[ "$ROOT_PART_TYPE" == "part" ]]; then
  pass_test "$ROOT_PART_DEV is a partition"
else
  fail_test "$ROOT_PART_DEV is not a partition (type: $ROOT_PART_TYPE)"
fi

# Test 6: Partition is at least 80% of disk
ROOT_DEVICE_SIZE=$(lsblk -nbdo SIZE "$ROOT_DEVICE_PATH")
ROOT_PART_SIZE=$(lsblk -nbdo SIZE "$ROOT_PART_DEV")
if (( ROOT_PART_SIZE > ROOT_DEVICE_SIZE * 8 / 10 )); then
  pass_test "Root partition uses at least 80% of disk (${ROOT_PART_SIZE} / ${ROOT_DEVICE_SIZE})"
else
  fail_test "Root partition is too small (${ROOT_PART_SIZE} / ${ROOT_DEVICE_SIZE})"
fi

# Test 7: Filesystem nearly fills partition
read -r AVAIL USED SIZE < <(df / --output=avail,used,size -B1 | tail -1)
if (( SIZE > ROOT_PART_SIZE * 98 / 100 )); then
  pass_test "Filesystem uses at least 98% of root partition (${SIZE} / ${ROOT_PART_SIZE})"
else
  fail_test "Filesystem too small for root partition (${SIZE} / ${ROOT_PART_SIZE})"
fi

# Test 8: Filesystem <50% used
if (( AVAIL > USED )); then
  pass_test "Filesystem is under 50% full (avail: ${AVAIL}, used: ${USED})"
else
  fail_test "Filesystem usage exceeds 50% (avail: ${AVAIL}, used: ${USED})"
fi

# Final result
if (( ALL_PASS )); then
  echo "PASS"
  exit 0
else
  echo "At least one test failed"
  if [[ -f /var/log/particle.log ]]; then
    echo "Logs from /var/log/particle.log:"
    cat /var/log/particle.log
    echo ""
  else
    echo "No log file found at /var/log/particle.log"
  fi
  echo "FAIL"
  exit 1
fi
