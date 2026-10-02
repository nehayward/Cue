#!/bin/bash
# Build Cue for a connected iPhone, install it and launch it.
#
#   Scripts/deploy-to-iphone.sh            # build Debug, install, launch
#   Scripts/deploy-to-iphone.sh --logs     # ...then capture 30s of console
#   Scripts/deploy-to-iphone.sh --logs 90  # ...or 90s
#   Scripts/deploy-to-iphone.sh --no-launch
#   Scripts/deploy-to-iphone.sh --no-watch # skip installing on the watch
#   CUE_DEVICE="Nick's iPhone" Scripts/deploy-to-iphone.sh
#   CUE_WATCH="Nick's Apple Watch" Scripts/deploy-to-iphone.sh
#
# The phone is chosen by Scripts/lib/iphone.sh. The watch app inside the
# build is installed straight onto the watch (the first one Xcode knows, or
# $CUE_WATCH), so the watch's reason shows here when it won't take it.
# Console capture and crash reports are handled by Scripts/iphone-logs.sh
# and Scripts/iphone-crashes.sh.

set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="${CUE_SCHEME:-Cue}"
CONFIGURATION="${CUE_CONFIGURATION:-Debug}"
DERIVED_DATA="build/DeviceDerivedData"
LAUNCH=1
WATCH=1
LOG_SECONDS=0
while [ $# -gt 0 ]; do
	case "$1" in
		--no-launch) LAUNCH=0 ;;
		--no-watch) WATCH=0 ;;
		--logs)
			LOG_SECONDS=30
			if [[ "${2:-}" =~ ^[0-9]+$ ]]; then LOG_SECONDS="$2"; shift; fi
			;;
		*) echo "error: unknown option $1" >&2; exit 1 ;;
	esac
	shift
done

step() { echo -e "\n==== $1 ====\n"; }
fail() { echo "error: $1" >&2; exit 1; }

command -v xcodebuild >/dev/null || fail "xcodebuild not found. Install Xcode."

source Scripts/lib/iphone.sh
resolve_iphone

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

# The iPhone only passes its watch app on when the Watch app's Automatic App
# Install is on, and says nothing when the watch refuses it. Installing it
# directly shows why (watchOS too old, Developer Mode off, watch missing
# from the provisioning profile).
WATCH_APP="$(ls -d "$APP/Watch/"*.app 2>/dev/null | head -1 || true)"
if [ "$WATCH" -eq 1 ] && [ -d "$WATCH_APP" ]; then
	WATCHES="$(Scripts/list-watches.py)"
	if [ -n "${CUE_WATCH:-}" ]; then
		WATCH_LINE="$(echo "$WATCHES" | awk -F'\t' -v w="$CUE_WATCH" '$1 == w || $2 == w' | head -1)"
	else
		WATCH_LINE="$(echo "$WATCHES" | head -1)"
	fi
	if [ -z "$WATCH_LINE" ]; then
		echo "No Apple Watch found. Open Xcode ▸ Window ▸ Devices and Simulators with the watch on its charger and unlocked, turn on Developer Mode on the watch (Settings ▸ Privacy & Security), then deploy again."
	else
		WATCH_UDID="$(echo "$WATCH_LINE" | cut -f1)"
		WATCH_NAME="$(echo "$WATCH_LINE" | cut -f2)"
		step "Installing $(basename "$WATCH_APP") on $WATCH_NAME"
		xcrun devicectl device install app --device "$WATCH_UDID" "$WATCH_APP" \
			|| echo "The watch didn't take it (above). Keep it unlocked and on its charger, check Developer Mode is on, and try again."
	fi
fi

if [ "$LAUNCH" -eq 1 ] && [ "$LOG_SECONDS" -gt 0 ]; then
	CUE_DEVICE="$UDID" CUE_BUNDLE_ID="$BUNDLE_ID" Scripts/iphone-logs.sh "$LOG_SECONDS"
elif [ "$LAUNCH" -eq 1 ]; then
	step "Launching $BUNDLE_ID"
	xcrun devicectl device process launch --terminate-existing --device "$UDID" "$BUNDLE_ID" \
		|| echo "Installed, but could not launch. Unlock the phone and open Cue."
fi

step "Done: $SCHEME is on $NAME"
