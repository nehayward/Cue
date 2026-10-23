#!/usr/bin/python3
"""Print the Apple Watches this Mac knows, one line per watch:
<udid>\t<name>\t<model>\t<state>

A watch is reached through its paired iPhone, and only once it has shown up
in Xcode ▸ Devices and Simulators with Developer Mode on.
"""
import json
import subprocess
import sys
import tempfile

with tempfile.NamedTemporaryFile(suffix=".json") as out:
    result = subprocess.run(
        ["xcrun", "devicectl", "list", "devices", "--json-output", out.name],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    if result.returncode != 0:
        sys.exit(0)
    devices = json.load(open(out.name)).get("result", {}).get("devices", [])

for d in devices:
    hw = d.get("hardwareProperties", {})
    if hw.get("platform") != "watchOS":
        continue
    # devicectl lists simulators too now; only a real watch takes an install.
    if hw.get("reality", "physical") != "physical":
        continue
    print("\t".join([
        hw.get("udid") or d.get("identifier", ""),
        d.get("deviceProperties", {}).get("name", "Apple Watch"),
        hw.get("marketingName") or hw.get("productType", ""),
        d.get("connectionProperties", {}).get("tunnelState", "unknown"),
    ]))
