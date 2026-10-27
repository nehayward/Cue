#!/usr/bin/env bash
# Cue's App Store screenshots and previews, made with Tools/StoreShots from
# Marketing/AppStore/storeshots.json. Builds the tool, then runs it.
#
# Usage:
#   Scripts/app-store-art.sh render              # every device's screenshots
#   Scripts/app-store-art.sh preview             # the App Preview and the promo
#   Scripts/app-store-art.sh banner              # the product page header and search art
#   Scripts/app-store-art.sh sheet               # a contact sheet per device
#   Scripts/app-store-art.sh shoot iphone radio  # the simulator's screen as a raw shot
#   Scripts/app-store-art.sh record iphone books --seconds 30
#
# Output goes to build/app-store/output. See Tools/StoreShots/README.md.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE="$ROOT/Tools/StoreShots"
PROJECT="$ROOT/Marketing/AppStore/storeshots.json"

if [[ $# -lt 1 ]]; then
	sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
	exit 64
fi

swift build -c release --package-path "$PACKAGE" >/dev/null
command="$1"
shift
if [[ "$command" == "devices" ]]; then
	exec "$PACKAGE/.build/release/storeshots" devices
fi
exec "$PACKAGE/.build/release/storeshots" "$command" "$PROJECT" "$@"
