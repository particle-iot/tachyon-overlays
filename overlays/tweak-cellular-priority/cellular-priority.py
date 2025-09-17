#!/usr/bin/env python3
import sys
from pathlib import Path

lib_path = Path("/usr/lib/libql_ril.so")

search_bytes = b"metric 500"
replace_bytes = b"metric 700"

if len(search_bytes) != len(replace_bytes):
    print("Error: search and replacement strings must be the same length")
    sys.exit(1)

data = lib_path.read_bytes()
count = data.count(search_bytes)

patched_data = data.replace(search_bytes, replace_bytes)
lib_path.write_bytes(patched_data)

if count != 0:
    print(f"Error: Found {count} occurrences of {search_bytes!r}, expected exactly 0.")
    sys.exit(1)

count = data.count(replace_bytes)

if count != 2:
    print(f"Error: Found {count} occurrences of {replace_bytes!r}, expected exactly 2.")
    sys.exit(1)

print(f"{lib_path} patched successfully.")
