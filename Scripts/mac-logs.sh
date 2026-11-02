#!/bin/bash
# Relaunch the built Cue (Mac) and capture its console for a while.
#
#   Scripts/mac-logs.sh          # capture 30 seconds
#   Scripts/mac-logs.sh 90       # capture 90 seconds
#   CUE_LOG_FILTER=route Scripts/mac-logs.sh   # only show matching lines
#
# Shows print() and Logger/os_log output. The app keeps running afterwards and
# keeps writing to build/mac-console.log. If Cue crashes during the capture,
# the crash report is shown at the end.

set -euo pipefail

cd "$(dirname "$0")/.."

SECONDS_TO_CAPTURE="${1:-30}"

step() { echo -e "\n==== $1 ====\n"; }
fail() { echo "error: $1" >&2; exit 1; }

source Scripts/lib/mac.sh
find_mac_app

STARTED="$(date +%s)"
step "Launching Cue on this Mac, capturing ${SECONDS_TO_CAPTURE}s of console"
echo "Use the app now to reproduce what you want to see."
launch_mac_app

EXITED=0
for _ in $(seq "$SECONDS_TO_CAPTURE"); do
	kill -0 "$MAC_PID" 2>/dev/null || { EXITED=1; break; }
	sleep 1
done

step "Console ($(wc -l <"$MAC_CONSOLE_LOG" | tr -d ' ') lines, full log: $MAC_CONSOLE_LOG)"
if [ -n "${CUE_LOG_FILTER:-}" ]; then
	grep -i -- "$CUE_LOG_FILTER" "$MAC_CONSOLE_LOG" | tail -200 || echo "(no lines match \"$CUE_LOG_FILTER\")"
else
	tail -200 "$MAC_CONSOLE_LOG"
fi

if [ "$EXITED" -eq 1 ]; then
	step "Cue exited during the capture; checking for a crash report"
	sleep 3 # the report is written a moment after the process dies
	Scripts/mac-crashes.sh --since "$STARTED" || true
fi
