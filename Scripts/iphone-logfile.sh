#!/bin/bash
# Pull Cue's log file off the iPhone: the same log Settings ▸ Report a
# Problem attaches to its email, without relaunching the app.
#
#   Scripts/iphone-logfile.sh          # show the last 200 lines
#   Scripts/iphone-logfile.sh 1000     # show the last 1000 lines
#   CUE_LOG_FILTER=route Scripts/iphone-logfile.sh   # only show matching lines
#
# Unlike Scripts/iphone-logs.sh, which watches the console live, this reaches
# back across launches and crashes, up to a week (see Docs/Logging.md). The
# files are copied to build/device-logfile/ and joined, oldest first, into
# build/device-logfile.log. Needs a build installed from Xcode or
# Scripts/deploy-to-iphone.sh: the system only lets development builds'
# containers be read.

set -euo pipefail

cd "$(dirname "$0")/.."

LINES_TO_SHOW="${1:-200}"
BUNDLE_ID="${CUE_BUNDLE_ID:-dance.cue}"
DIR="build/device-logfile"
LOG="build/device-logfile.log"

step() { echo -e "\n==== $1 ====\n"; }
fail() { echo "error: $1" >&2; exit 1; }

source Scripts/lib/iphone.sh
resolve_iphone

step "Copying Cue's log files from $NAME"
rm -rf "$DIR"
mkdir -p "$DIR"
xcrun devicectl device copy from \
	--device "$UDID" \
	--domain-type appDataContainer \
	--domain-identifier "$BUNDLE_ID" \
	--source Library/Logs/Cue \
	--destination "$DIR" >/dev/null \
	|| fail "Couldn't copy the log files. Is a development build of Cue installed on $NAME?"

# The names sort by when each file started.
FILES="$(find "$DIR" -type f -name 'Cue-*.log' | sort)"
[ -n "$FILES" ] || fail "Cue hasn't written a log file on $NAME yet."
# shellcheck disable=SC2086
cat $FILES >"$LOG"

step "Log ($(echo "$FILES" | wc -l | tr -d ' ') files, $(wc -l <"$LOG" | tr -d ' ') lines, full log: $LOG)"
if [ -n "${CUE_LOG_FILTER:-}" ]; then
	grep -i -- "$CUE_LOG_FILTER" "$LOG" | tail -"$LINES_TO_SHOW" || echo "(no lines match \"$CUE_LOG_FILTER\")"
else
	tail -"$LINES_TO_SHOW" "$LOG"
fi
