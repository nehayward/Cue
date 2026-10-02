#!/bin/bash
# Relaunch Cue on the iPhone and capture its console for a while.
#
#   Scripts/iphone-logs.sh          # capture 30 seconds
#   Scripts/iphone-logs.sh 90       # capture 90 seconds
#   CUE_LOG_FILTER=route Scripts/iphone-logs.sh   # only show matching lines
#
# Captures print() output and Logger/os_log messages (OS_ACTIVITY_DT_MODE
# sends those to the console the way Xcode does). The full capture goes to
# build/device-console.log. If Cue crashes during the capture, the crash
# report is pulled and symbolicated at the end.

set -euo pipefail

cd "$(dirname "$0")/.."

SECONDS_TO_CAPTURE="${1:-30}"
BUNDLE_ID="${CUE_BUNDLE_ID:-dance.cue}"
LOG="build/device-console.log"

step() { echo -e "\n==== $1 ====\n"; }
fail() { echo "error: $1" >&2; exit 1; }

source Scripts/lib/iphone.sh
resolve_iphone

mkdir -p build
STARTED="$(date +%s)"

step "Launching $BUNDLE_ID on $NAME, capturing ${SECONDS_TO_CAPTURE}s of console"
echo "Use the app on the phone now to reproduce what you want to see."
xcrun devicectl device process launch \
	--console \
	--terminate-existing \
	--environment-variables '{"OS_ACTIVITY_DT_MODE": "enable"}' \
	--device "$UDID" \
	"$BUNDLE_ID" >"$LOG" 2>&1 &
PID=$!

# Stop early if the app exits (devicectl returns when the process ends).
for _ in $(seq "$SECONDS_TO_CAPTURE"); do
	kill -0 "$PID" 2>/dev/null || break
	sleep 1
done
if kill -0 "$PID" 2>/dev/null; then
	kill "$PID" 2>/dev/null || true
	EXITED=0
else
	EXITED=1
fi
wait "$PID" 2>/dev/null || true

step "Console ($(wc -l <"$LOG" | tr -d ' ') lines, full log: $LOG)"
if [ -n "${CUE_LOG_FILTER:-}" ]; then
	grep -i -- "$CUE_LOG_FILTER" "$LOG" | tail -200 || echo "(no lines match \"$CUE_LOG_FILTER\")"
else
	tail -200 "$LOG"
fi

if [ "$EXITED" -eq 1 ]; then
	step "Cue exited during the capture; checking for a crash report"
	Scripts/iphone-crashes.sh --since "$STARTED" || true
fi
