#!/bin/bash
# Start Claude Code on this Mac so you can drive it from the Claude app on
# your phone. Claude edits, builds and installs Cue on your iPhone from here.
#
#   Scripts/claude-remote.sh            # check setup, pick iPhone, start
#   Scripts/claude-remote.sh --pick     # choose a different iPhone first
#
# The Mac is kept awake (caffeinate) for as long as the session runs.

set -euo pipefail

cd "$(dirname "$0")/.."

step() { echo -e "\n==== $1 ====\n"; }
fail() { echo "error: $1" >&2; exit 1; }

[ "$(uname)" = "Darwin" ] || fail "Run this on your Mac."

step "Checking tools"
command -v xcodebuild >/dev/null || fail "Xcode is not installed."
xcrun devicectl --version >/dev/null 2>&1 || fail "devicectl missing. Update Xcode (15 or later) and open it once."
if ! command -v claude >/dev/null; then
	echo "Claude Code is not installed. Install it with:"
	echo "  curl -fsSL https://claude.ai/install.sh | bash"
	echo "then run 'claude' once to sign in, and re-run this script."
	exit 1
fi
echo "Xcode, devicectl and claude found."

step "Choosing iPhone"
if [ "${1:-}" = "--pick" ] || [ ! -f .cue-device ]; then
	JSON="$(mktemp)"
	xcrun devicectl list devices --json-output "$JSON" >/dev/null 2>&1 || true
	NAMES=()
	while IFS= read -r line; do [ -n "$line" ] && NAMES+=("$line"); done < <(
		/usr/bin/python3 - "$JSON" <<'PY' 2>/dev/null
import json, sys
for d in json.load(open(sys.argv[1])).get("result", {}).get("devices", []):
    hw = d.get("hardwareProperties", {})
    if hw.get("platform") == "iOS" and hw.get("deviceType") == "iPhone":
        print(d.get("deviceProperties", {}).get("name", "iPhone"))
PY
	)
	rm -f "$JSON"

	if [ "${#NAMES[@]}" -eq 0 ]; then
		echo "No iPhone found. Plug it in, unlock it, trust this Mac, and turn on"
		echo "Developer Mode (Settings ▸ Privacy & Security). Pair it once in"
		echo "Xcode ▸ Window ▸ Devices and Simulators to deploy over Wi-Fi."
		echo "Continuing; Claude will fall back to simulator builds until then."
	elif [ "${#NAMES[@]}" -eq 1 ]; then
		echo "${NAMES[0]}" > .cue-device
	else
		echo "Which iPhone should Claude deploy to?"
		select name in "${NAMES[@]}"; do [ -n "$name" ] && { echo "$name" > .cue-device; break; }; done
	fi
fi
[ -f .cue-device ] && echo "Deploying to: $(cat .cue-device)"

step "Updating main"
if [ -n "$(git status --porcelain)" ]; then
	echo "You have uncommitted changes on $(git branch --show-current); leaving the checkout as is."
else
	git fetch origin main --quiet && echo "Fetched origin/main. Claude will branch from it."
fi

step "Starting Claude Code remote control"
echo "Open the Claude app on your phone ▸ Code to find this session."
echo "Keep this window open. Ctrl-C to stop."
exec caffeinate -dimsu claude remote-control
