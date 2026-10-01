#!/bin/bash
# Show Cue's newest crash reports from the iPhone, symbolicated.
#
#   Scripts/iphone-crashes.sh                 # newest crash
#   Scripts/iphone-crashes.sh --count 3       # newest three
#   Scripts/iphone-crashes.sh --since EPOCH   # only crashes after a time
#   Scripts/iphone-crashes.sh --process Widgets
#
# Reports are copied to build/crashes. Frames in Cue's own code are
# symbolicated against the last build from Scripts/deploy-to-iphone.sh.

set -euo pipefail

cd "$(dirname "$0")/.."

fail() { echo "error: $1" >&2; exit 1; }

source Scripts/lib/iphone.sh
resolve_iphone

echo "Reading crash reports from $NAME"
exec Scripts/crash-report.py "$UDID" "$@"
