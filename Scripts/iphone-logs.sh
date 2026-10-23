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

launch() {
	xcrun devicectl device process launch \
		--console \
		--terminate-existing \
		--environment-variables '{"OS_ACTIVITY_DT_MODE": "enable"}' \
		--device "$UDID" \
		"$BUNDLE_ID" >"$LOG" 2>&1 &
	PID=$!
}

# A locked phone refuses the launch. Driven from the phone, it's often
# locked when this starts, so keep asking until it's unlocked (up to
# $CUE_UNLOCK_WAIT seconds), and count the capture from the launch.
is_locked() { grep -q "could not be, unlocked" "$LOG"; }
UNLOCK_WAIT="${CUE_UNLOCK_WAIT:-120}"
UNLOCK_DEADLINE=$(( $(date +%s) + UNLOCK_WAIT ))
DEADLINE=$(( $(date +%s) + SECONDS_TO_CAPTURE ))
TOLD_LOCKED=0
launch

# Stop early if the app exits (devicectl returns when the process ends).
while :; do
	if ! kill -0 "$PID" 2>/dev/null; then
		wait "$PID" 2>/dev/null || true
		if is_locked && [ "$(date +%s)" -lt "$UNLOCK_DEADLINE" ]; then
			if [ "$TOLD_LOCKED" -eq 0 ]; then
				echo "The phone is locked. Unlock it and the capture starts (waiting up to ${UNLOCK_WAIT}s)..."
				TOLD_LOCKED=1
			fi
			sleep 3
			STARTED="$(date +%s)"
			DEADLINE=$(( STARTED + SECONDS_TO_CAPTURE ))
			launch
			continue
		fi
		EXITED=1
		break
	fi
	if [ "$(date +%s)" -ge "$DEADLINE" ]; then
		kill "$PID" 2>/dev/null || true
		wait "$PID" 2>/dev/null || true
		EXITED=0
		break
	fi
	sleep 1
done

if is_locked; then
	fail "Cue couldn't launch: the phone stayed locked for ${UNLOCK_WAIT}s. Unlock it and run this again."
fi

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
