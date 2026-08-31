#!/usr/bin/env python3

import os
import struct
import json
import subprocess
import datetime

BLOB_PATH = "/dev/disk/by-partlabel/misc"

# Only used if the kernel does not report a size for the backing device, which it
# should always do for a real partition. `misc` is 1 MiB today.
FALLBACK_BLOB_LIMIT = 1024 * 1024


def partition_size(f) -> int:
    """Size of the backing partition, in bytes, as the kernel reports it.

    `os.stat().st_size` is 0 for a block device, so seek to the end instead -- that
    returns the real size (1048576 for `misc`, matching `blockdev --getsize64`).
    """
    size = f.seek(0, os.SEEK_END)
    f.seek(0)
    return size


def read_bootstrap_time(path: str):
    """Return the setup timestamp from the config blob, or None if there is not one.

    A zeroed partition is the normal steady state, not a fault: `particle-linux`
    erases the blob once it has applied it, so every boot after the first finds
    nothing here. Ditto a blob written by a CLI old enough not to stamp
    `initialTime`. Both return None. Anything else -- a truncated read, an absurd
    length, malformed JSON -- raises, because that is a real anomaly worth naming.
    """
    with open(path, "rb") as f:
        header = f.read(4)
        if len(header) < 4:
            raise ValueError("blob is too short to contain a size header")

        size = struct.unpack(">I", header)[0]  # Big-endian uint32
        if size == 0:
            return None

        # The size field is four bytes read straight off the partition, so a single
        # flipped bit can claim up to 4 GiB. The partition itself is the natural
        # bound: a blob cannot be larger than the thing holding it, less the four
        # bytes the header already took.
        limit = (partition_size(f) or FALLBACK_BLOB_LIMIT) - 4
        f.seek(4)
        if size > limit:
            raise ValueError(f"blob declares {size} bytes, more than the {limit} bytes the partition holds")

        data = f.read(size)
        if len(data) < size:
            raise ValueError(f"blob declares {size} bytes but only {len(data)} are readable")

        obj = json.loads(data.decode("utf-8"))

    # `particle tachyon setup` stamps this with the host's clock at the moment it
    # built the blob, as an ISO-8601 UTC string ending in `Z`.
    initial_time = obj.get("initialTime")
    if not initial_time:
        return None

    return datetime.datetime.fromisoformat(initial_time.replace("Z", "+00:00"))


def set_system_time(when: datetime.datetime):
    subprocess.run(["date", "-s", when.isoformat()], check=True)


def main():
    # The board has no battery-backed clock, so it starts at the epoch and systemd
    # then drags it forward to whenever the image was built. Either way the clock is
    # behind the moment `particle tachyon setup` ran, which is what the blob records.
    #
    # Comparing against that recorded moment is the whole test: if our clock is
    # already at or past it, something trustworthy (systemd-timesyncd, a previous
    # boot) has set the time and we must not drag it backwards. This deliberately
    # replaces a `current_year == 2024` check, which stopped matching anything on
    # 1 January 2025 and silently turned this service into a no-op.
    try:
        bootstrap_time = read_bootstrap_time(BLOB_PATH)
    except Exception as e:
        # Keep the unit green -- a clock we could not correct is not worth failing
        # boot over -- but say what actually went wrong. Reporting every failure as
        # "not available" hides a corrupt partition behind the same line as an
        # ordinary erased one, which is exactly the case someone will need to debug.
        print(f"[set-initial-time] Could not read {BLOB_PATH}: {type(e).__name__}: {e}")
        return

    if bootstrap_time is None:
        print("[set-initial-time] No setup time recorded. Skipping.")
        return

    now = datetime.datetime.now(datetime.timezone.utc)
    if now >= bootstrap_time:
        print(f"[set-initial-time] Current time {now.isoformat()} is at or past "
              f"the setup time {bootstrap_time.isoformat()}. Skipping.")
        return

    print(f"[set-initial-time] Current time {now.isoformat()} predates setup; "
          f"setting time to: {bootstrap_time.isoformat()}")
    try:
        set_system_time(bootstrap_time)
    except Exception as e:
        print(f"[set-initial-time] Failed to set the time: {type(e).__name__}: {e}")


if __name__ == "__main__":
    main()
