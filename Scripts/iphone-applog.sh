#!/bin/bash
# Copy Cue's own log files off the iPhone and show the newest. No password,
# and nothing to do on the phone: a Debug build writes them as it runs
# (Cue/Debug/PhoneLogFile.swift), a file a launch, the newest five kept.
#
#   Scripts/iphone-applog.sh                  # last 200 lines of the newest
#   Scripts/iphone-applog.sh 500              # last 500
#   CUE_LOG_FILTER=audiobooks Scripts/iphone-applog.sh   # only matching lines
#
# The files land in build/phone-logs.

set -euo pipefail

cd "$(dirname "$0")/.."

LINES="${1:-200}"
OUT="build/phone-logs"

fail() { echo "error: $1" >&2; exit 1; }

source Scripts/lib/iphone.sh
resolve_iphone

rm -rf "$OUT"
mkdir -p "$OUT"
echo "Copying Cue's logs from $NAME"
xcrun devicectl device copy from --device "$UDID" \
	--domain-type appDataContainer --domain-identifier dance.cue \
	--source Library/Logs/Cue --destination "$OUT" >/dev/null \
	|| fail "Couldn't copy the logs. Is a Debug build of Cue on the phone, and has it run since?"

NEWEST="$(ls -t "$OUT"/*.log 2>/dev/null | head -1)"
[ -n "$NEWEST" ] || fail "No log files yet. Open Cue on the phone and try again."
echo "Files: $(ls "$OUT" | tr '\n' ' ')"
echo "==== $(basename "$NEWEST") ===="
if [ -n "${CUE_LOG_FILTER:-}" ]; then
	grep -i -- "$CUE_LOG_FILTER" "$NEWEST" | tail -n "$LINES"
else
	tail -n "$LINES" "$NEWEST"
fi
