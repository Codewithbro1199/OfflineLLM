"""Reads `xcrun simctl list devices available -j` from stdin and prints the newest iPhone simulator's UDID."""
import json
import re
import sys

data = json.load(sys.stdin)
best = None
for runtime, devices in data.get("devices", {}).items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    for device in devices:
        if not device.get("isAvailable") or not device["name"].startswith("iPhone"):
            continue
        rank = (version, "Pro" in device["name"])
        if best is None or rank > best[0]:
            best = (rank, device["udid"])

if best is None:
    sys.exit("No available iPhone simulator found")
print(best[1])
