#!/usr/bin/python3
"""Pull Cue crash reports off an iPhone and print them symbolicated.

    crash-report.py <udid> [--since EPOCH] [--count N] [--process Cue] [--app PATH]

Copies the newest crash reports for the process into build/crashes and
prints a summary of each: exception, crash message, and the crashed
thread's backtrace. Frames in Cue's own binaries are symbolicated against
the app in build/DeviceDerivedData with atos, so the build must be the one
that crashed (the UUID is checked and a mismatch is reported).
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CRASH_DIR = os.path.join(ROOT, "build", "crashes")
DEFAULT_APP = os.path.join(ROOT, "build", "DeviceDerivedData", "Build", "Products", "Debug-iphoneos", "Cue.app")
STAMP = re.compile(r"-(\d{4}-\d{2}-\d{2}-\d{6})(?:\.\d+)?\.ips$")


def devicectl(*args):
    with tempfile.NamedTemporaryFile(suffix=".json") as out:
        result = subprocess.run(
            ["xcrun", "devicectl", *args, "--json-output", out.name],
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True,
        )
        if result.returncode != 0:
            sys.exit(f"error: devicectl {' '.join(args[:3])} failed:\n{result.stderr.strip()}")
        return json.load(open(out.name))


def ips_paths(node):
    """Every string ending in .ips anywhere in devicectl's JSON."""
    if isinstance(node, dict):
        for value in node.values():
            yield from ips_paths(value)
    elif isinstance(node, list):
        for value in node:
            yield from ips_paths(value)
    elif isinstance(node, str) and node.endswith(".ips"):
        yield node


def crash_time(path):
    match = STAMP.search(path)
    if not match:
        return 0
    return time.mktime(time.strptime(match.group(1), "%Y-%m-%d-%H%M%S"))


def find_crashes(udid, process, since, count):
    listing = devicectl("device", "info", "files", "--device", udid, "--domain-type", "systemCrashLogs")
    by_name = {}
    for path in ips_paths(listing):
        name = os.path.basename(path)
        if name.startswith(f"{process}-") and len(path) > len(by_name.get(name, "")):
            by_name[name] = path
    crashes = sorted(by_name.values(), key=crash_time, reverse=True)
    if since:
        crashes = [c for c in crashes if crash_time(c) >= since - 60]
    return crashes[:count]


def copy_crash(udid, source):
    os.makedirs(CRASH_DIR, exist_ok=True)
    destination = os.path.join(CRASH_DIR, os.path.basename(source))
    if not os.path.exists(destination):
        devicectl("device", "copy", "from", "--device", udid, "--domain-type", "systemCrashLogs",
                  "--source", source, "--destination", destination)
    return destination


def load_ips(path):
    text = open(path).read()
    header, _, body = text.partition("\n")
    return json.loads(header), json.loads(body)


def local_binary(image, app):
    path = image.get("path", "")
    if ".app/" not in path or not os.path.isdir(app):
        return None
    candidate = os.path.join(app, path.split(".app/", 1)[1])
    return candidate if os.path.exists(candidate) else None


def uuid_matches(binary, uuid):
    out = subprocess.run(["xcrun", "dwarfdump", "--uuid", binary], capture_output=True, text=True).stdout
    return uuid.replace("-", "").upper() in out.replace("-", "").upper()


def symbolicate(frames_list, images, app):
    """Fill in 'symbol' for frames in Cue's binaries using atos."""
    wanted = {}
    for frames in frames_list:
        for frame in frames:
            index = frame.get("imageIndex")
            if index is None or index >= len(images):
                continue
            if local_binary(images[index], app):
                wanted.setdefault(index, set()).add(frame["imageOffset"])

    resolved, stale = {}, []
    for index, offsets in wanted.items():
        image = images[index]
        binary = local_binary(image, app)
        if image.get("uuid") and not uuid_matches(binary, image["uuid"]):
            stale.append(image.get("name", binary))
            continue
        offsets = sorted(offsets)
        base = image["base"]
        out = subprocess.run(
            ["xcrun", "atos", "-arch", "arm64", "-o", binary, "-l", hex(base),
             *[hex(base + offset) for offset in offsets]],
            capture_output=True, text=True,
        ).stdout.splitlines()
        for offset, line in zip(offsets, out):
            resolved[(index, offset)] = line.strip()

    for frames in frames_list:
        for frame in frames:
            key = (frame.get("imageIndex"), frame.get("imageOffset"))
            if key in resolved:
                frame["symbol"] = resolved[key]
                frame.pop("symbolLocation", None)
    return stale


def format_frames(frames, images, limit=30):
    lines = []
    for number, frame in enumerate(frames[:limit]):
        index = frame.get("imageIndex")
        image = images[index].get("name", "?") if index is not None and index < len(images) else "?"
        symbol = frame.get("symbol")
        if symbol:
            if frame.get("symbolLocation"):
                symbol += f" + {frame['symbolLocation']}"
        else:
            symbol = f"{image} + {frame.get('imageOffset', 0):#x}"
        lines.append(f"  {number:<3} {image:<28} {symbol}")
    if len(frames) > limit:
        lines.append(f"  ... {len(frames) - limit} more frames")
    return "\n".join(lines)


def report(path, app):
    header, body = load_ips(path)
    images = body.get("usedImages", [])
    threads = body.get("threads", [])
    faulting = body.get("faultingThread", 0)
    crashed = threads[faulting] if faulting < len(threads) else {"frames": []}
    exception_bt = body.get("lastExceptionBacktrace")

    stale = symbolicate([crashed.get("frames", []), exception_bt or []], images, app)

    exception = body.get("exception", {})
    termination = body.get("termination", {})
    print(f"Crash: {os.path.basename(path)}")
    print(f"  App {header.get('app_version', '?')} ({header.get('build_version', '?')}), "
          f"{header.get('os_version', '?')}, {header.get('timestamp', '?')}")
    print(f"  Exception: {exception.get('type', '?')} ({exception.get('signal', '?')})"
          + (f" {exception['subtype']}" if exception.get("subtype") else ""))
    if termination.get("indicator"):
        print(f"  Termination: {termination['indicator']}")
    for messages in (body.get("asi") or {}).values():
        for message in messages:
            print(f"  Message: {message}")
    if stale:
        print(f"  Note: {', '.join(stale)} on the phone is not the local build, so Cue frames"
              " are not symbolicated. Re-deploy and reproduce to get symbols.")

    if exception_bt:
        print("\nLast exception backtrace:")
        print(format_frames(exception_bt, images))
    name = crashed.get("name") or crashed.get("queue") or ""
    print(f"\nCrashed thread {faulting}{f' ({name})' if name else ''}:")
    print(format_frames(crashed.get("frames", []), images))
    print(f"\nFull report: {path}\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("udid")
    parser.add_argument("--since", type=float, default=0)
    parser.add_argument("--count", type=int, default=1)
    parser.add_argument("--process", default="Cue")
    parser.add_argument("--app", default=DEFAULT_APP)
    args = parser.parse_args()

    crashes = find_crashes(args.udid, args.process, args.since, args.count)
    if not crashes:
        print(f"No {args.process} crash reports" + (" since the launch." if args.since else " on the phone."))
        print("Some crashes (watchdog kills, out of memory) show up a minute later, or only in"
              " Settings ▸ Privacy & Security ▸ Analytics & Improvements ▸ Analytics Data.")
        return
    for source in crashes:
        report(copy_crash(args.udid, source), args.app)


if __name__ == "__main__":
    main()
