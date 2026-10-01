#!/bin/bash
# Build Cue for a connected iPhone, install it and launch it.
#
#   Scripts/deploy-to-iphone.sh            # build Debug, install, launch
#   Scripts/deploy-to-iphone.sh --logs     # ...then capture 30s of console
#   Scripts/deploy-to-iphone.sh --logs 90  # ...or 90s
#   Scripts/deploy-to-iphone.sh --no-launch
#   CUE_DEVICE="Nick's iPhone" Scripts/deploy-to-iphone.sh
#
# The phone is chosen by Scripts/lib/iphone.sh. Console capture and crash
# reports are handled by Scripts/iphone-logs.sh and Scripts/iphone-crashes.sh.

set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="${CUE_SCHEME:-Cue}"
CONFIGURATION="${CUE_CONFIGURATION:-Debug}"
DERIVED_DATA="build/DeviceDerivedData"
LAUNCH=1
LOG_SECONDS=0
while [ $# -gt 0 ]; do
	case "$1" in
		--no-launch) LAUNCH=0 ;;
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

if [ "$LAUNCH" -eq 1 ] && [ "$LOG_SECONDS" -gt 0 ]; then
	CUE_DEVICE="$UDID" CUE_BUNDLE_ID="$BUNDLE_ID" Scripts/iphone-logs.sh "$LOG_SECONDS"
elif [ "$LAUNCH" -eq 1 ]; then
	step "Launching $BUNDLE_ID"
	xcrun devicectl device process launch --terminate-existing --device "$UDID" "$BUNDLE_ID" \
		|| echo "Installed, but could not launch. Unlock the phone and open Cue."
fi

step "Done: $SCHEME is on $NAME"
