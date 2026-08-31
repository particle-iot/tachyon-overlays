#!/usr/bin/env python3

import struct
import json
import subprocess
import datetime

BLOB_PATH = "/dev/disk/by-partlabel/misc"


def read_bootstrap_time(path: str) -> datetime.datetime:
    with open(path, "rb") as f:
        header = f.read(4)
        if len(header) < 4:
            raise ValueError("Blob too short to contain size header")

        size = struct.unpack(">I", header)[0]  # Big-endian uint32
        if size == 0:
            raise ValueError("Blob is empty; nothing to read")

        data = f.read(size)
        if len(data) < size:
            raise ValueError("Blob content shorter than declared size")

        obj = json.loads(data.decode("utf-8"))
        # `particle tachyon setup` stamps this with the host's clock at the moment
        # it built the blob, as an ISO-8601 UTC string ending in `Z`.
        return datetime.datetime.fromisoformat(obj["initialTime"].replace("Z", "+00:00"))


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
    except Exception:
        print("[set-initial-time] No initial time is available. Skipping.")
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
        print(f"[set-initial-time] Failed to set the time: {e}")


if __name__ == "__main__":
    main()
