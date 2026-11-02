#!/bin/bash
# Show Cue's newest crash reports from this Mac, symbolicated.
#
#   Scripts/mac-crashes.sh                 # newest crash
#   Scripts/mac-crashes.sh --count 3       # newest three
#   Scripts/mac-crashes.sh --since EPOCH   # only crashes after a time
#   Scripts/mac-crashes.sh --process "Cue Mini"
#
# Reports are read from ~/Library/Logs/DiagnosticReports and copied to
# build/crashes. Frames in Cue's own code are symbolicated against the last
# build from Scripts/deploy-to-mac.sh.

set -euo pipefail

cd "$(dirname "$0")/.."

fail() { echo "error: $1" >&2; exit 1; }

source Scripts/lib/mac.sh
find_mac_app

exec Scripts/crash-report.py --mac --app "$MAC_APP" "$@"
