#!/usr/bin/python3
"""Print the iPhones this Mac can reach right now, USB first, then those
already connected over the network.

One line per phone: <udid>\t<name>\t<model>\t<USB|Wi-Fi>
Phones that are paired but not plugged in or on the network are skipped.
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

phones = []
for d in devices:
    hw = d.get("hardwareProperties", {})
    conn = d.get("connectionProperties", {})
    if hw.get("platform") != "iOS" or hw.get("deviceType") != "iPhone":
        continue
    # devicectl lists simulators too now, as connected over "sameMachine".
    if hw.get("reality", "physical") != "physical":
        continue
    transport = conn.get("transportType")
    if not transport and conn.get("tunnelState") != "connected":
        continue
    # USB, then a phone already connected over the network, then one that
    # is only known to be on it.
    if transport == "wired":
        rank = 0
    elif conn.get("tunnelState") == "connected":
        rank = 1
    else:
        rank = 2
    phones.append((
        rank,
        hw.get("udid") or d.get("identifier", ""),
        d.get("deviceProperties", {}).get("name", "iPhone"),
        hw.get("marketingName") or hw.get("productType", ""),
        "USB" if transport == "wired" else "Wi-Fi",
    ))

for _, udid, name, model, link in sorted(phones):
    print(f"{udid}\t{name}\t{model}\t{link}")
