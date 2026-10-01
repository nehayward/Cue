#!/bin/bash
# Build Cue for a connected iPhone, install it and launch it.
#
#   Scripts/deploy-to-iphone.sh            # build Debug, install, launch
#   Scripts/deploy-to-iphone.sh --no-launch
#   CUE_DEVICE="Nick's iPhone" Scripts/deploy-to-iphone.sh
#
# The device is picked in this order: $CUE_DEVICE (name or UDID), the one
# saved by Scripts/claude-remote.sh in .cue-device, then the first iPhone
# that is connected (USB or paired over Wi-Fi).

set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="${CUE_SCHEME:-Cue}"
CONFIGURATION="${CUE_CONFIGURATION:-Debug}"
DERIVED_DATA="build/DeviceDerivedData"
LAUNCH=1
[ "${1:-}" = "--no-launch" ] && LAUNCH=0

step() { echo -e "\n==== $1 ====\n"; }
fail() { echo "error: $1" >&2; exit 1; }

command -v xcodebuild >/dev/null || fail "xcodebuild not found. Install Xcode."

# Prints "<udid>\t<name>" for each connected iPhone.
connected_iphones() {
	local json
	json="$(mktemp)"
	xcrun devicectl list devices --json-output "$json" >/dev/null 2>&1 || { rm -f "$json"; return 0; }
	/usr/bin/python3 - "$json" <<'PY'
import json, sys
devices = json.load(open(sys.argv[1])).get("result", {}).get("devices", [])
for d in devices:
    hw = d.get("hardwareProperties", {})
    if hw.get("platform") != "iOS" or hw.get("deviceType") != "iPhone":
        continue
    if d.get("connectionProperties", {}).get("tunnelState") == "unavailable":
        continue
    print(f'{hw.get("udid", d.get("identifier"))}\t{d.get("deviceProperties", {}).get("name", "iPhone")}')
PY
	rm -f "$json"
}

WANTED="${CUE_DEVICE:-}"
[ -z "$WANTED" ] && [ -f .cue-device ] && WANTED="$(cat .cue-device)"

DEVICES="$(connected_iphones)"
[ -n "$DEVICES" ] || fail "No iPhone connected. Plug it in (or pair it over Wi-Fi in Xcode ▸ Devices), unlock it, and make sure Developer Mode is on."

if [ -n "$WANTED" ]; then
	LINE="$(echo "$DEVICES" | awk -F'\t' -v w="$WANTED" '$1 == w || $2 == w' | head -1)"
	[ -n "$LINE" ] || fail "\"$WANTED\" is not connected. Connected iPhones:
$(echo "$DEVICES" | cut -f2)"
else
	LINE="$(echo "$DEVICES" | head -1)"
fi
UDID="$(echo "$LINE" | cut -f1)"
NAME="$(echo "$LINE" | cut -f2)"

step "Building $SCHEME ($CONFIGURATION) for $NAME"
mkdir -p build
LOG="build/device-build.log"
if ! xcodebuild \
	-project Cue.xcodeproj \
	-scheme "$SCHEME" \
	-configuration "$CONFIGURATION" \
	-destination "id=$UDID" \
	-derivedDataPath "$DERIVED_DATA" \
	-allowProvisioningUpdates \
	build >"$LOG" 2>&1; then
	grep -E "error:" "$LOG" | sort -u | head -40 >&2 || true
	fail "Build failed. Full log: $LOG"
fi
echo "Build succeeded (log: $LOG)"

APP="$(ls -d "$DERIVED_DATA/Build/Products/$CONFIGURATION-iphoneos/"*.app 2>/dev/null | head -1)"
[ -d "$APP" ] || fail "Built app not found in $DERIVED_DATA/Build/Products/$CONFIGURATION-iphoneos"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")"

step "Installing $(basename "$APP") on $NAME"
xcrun devicectl device install app --device "$UDID" "$APP"

if [ "$LAUNCH" -eq 1 ]; then
	step "Launching $BUNDLE_ID"
	xcrun devicectl device process launch --terminate-existing --device "$UDID" "$BUNDLE_ID" \
		|| echo "Installed, but could not launch. Unlock the phone and open Cue."
fi

step "Done: $SCHEME is on $NAME"
