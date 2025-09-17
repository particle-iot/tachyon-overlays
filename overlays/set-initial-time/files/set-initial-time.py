#!/usr/bin/env python3

import struct
import json
import subprocess
import datetime

BLOB_PATH = "/dev/disk/by-partlabel/misc"

def is_time_bad() -> bool:
    current_year = datetime.datetime.utcnow().year
    return current_year == 2024

def read_bootstrap_time(path: str) -> str:
    with open(path, "rb") as f:
        header = f.read(4)
        if len(header) < 4:
            raise ValueError("Blob too short to contain size header")
        
        size = struct.unpack(">I", header)[0]  # Big-endian uint32
        data = f.read(size)
        if len(data) < size:
            raise ValueError("Blob content shorter than declared size")

        obj = json.loads(data.decode("utf-8"))
        return obj["initialTime"]

def set_system_time(timestr: str):
    subprocess.run(["date", "-s", timestr], check=True)

def main():
    if not is_time_bad():
        print("[set-initial-time] Current time is valid. Skipping.")
        return

    try:
        timestr = read_bootstrap_time(BLOB_PATH)
        print(f"[set-initial-time] Setting time to: {timestr}")
        set_system_time(timestr)
    except Exception as e:
        print(f"[set-initial-time] Current time is invalid, but no initial time is available.")

if __name__ == "__main__":
    main()
