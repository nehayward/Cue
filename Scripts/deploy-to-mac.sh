#!/bin/bash
# Build Cue (Mac) and run it on this Mac.
#
#   Scripts/deploy-to-mac.sh             # build Debug, quit any running Cue, launch
#   Scripts/deploy-to-mac.sh --logs      # ...then show 30s of console
#   Scripts/deploy-to-mac.sh --logs 90   # ...or 90s
#   Scripts/deploy-to-mac.sh --no-launch
#
# The app runs from ~/Library/Developer/Xcode/DerivedData/Cue-Mac; its console goes to
# build/mac-console.log. Logs, crashes and memory profiling are handled by
# Scripts/mac-logs.sh, Scripts/mac-crashes.sh and Scripts/mac-profile.sh.

set -euo pipefail

cd "$(dirname "$0")/.."

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

[ "$(uname)" = "Darwin" ] || fail "Run this on your Mac."
command -v xcodebuild >/dev/null || fail "xcodebuild not found. Install Xcode."

source Scripts/lib/mac.sh

step "Building $MAC_SCHEME ($MAC_CONFIGURATION) for this Mac"
build_mac
find_mac_app

if [ "$LAUNCH" -eq 0 ]; then
	step "Done: built $MAC_APP"
	exit 0
fi

if [ "$LOG_SECONDS" -gt 0 ]; then
	exec Scripts/mac-logs.sh "$LOG_SECONDS"
fi

step "Launching $MAC_APP"
launch_mac_app
step "Done: Cue is running on this Mac (pid $MAC_PID, console: $MAC_CONSOLE_LOG)"
