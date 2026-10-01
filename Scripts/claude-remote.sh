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
	# Only phones reachable right now, USB first: udid, name, model, link.
	PHONES=()
	while IFS= read -r line; do [ -n "$line" ] && PHONES+=("$line"); done < <(Scripts/list-iphones.py)

	if [ "${#PHONES[@]}" -eq 0 ]; then
		echo "No iPhone connected. Plug it in with a cable, unlock it, trust this Mac,"
		echo "and turn on Developer Mode (Settings ▸ Privacy & Security). Then run"
		echo "Scripts/claude-remote.sh --pick. Until then Claude builds for the simulator."
	elif [ "${#PHONES[@]}" -eq 1 ]; then
		echo "${PHONES[0]}" | cut -f1 > .cue-device
	else
		LABELS=()
		for p in "${PHONES[@]}"; do
			LABELS+=("$(echo "$p" | awk -F'\t' '{ printf "%s (%s, %s)", $2, $3, $4 }')")
		done
		echo "Which iPhone should Claude deploy to?"
		select label in "${LABELS[@]}"; do
			[ -n "$label" ] && { echo "${PHONES[$((REPLY - 1))]}" | cut -f1 > .cue-device; break; }
		done
	fi
fi
if [ -f .cue-device ]; then
	CHOSEN="$(Scripts/list-iphones.py | awk -F'\t' -v id="$(cat .cue-device)" '$1 == id || $2 == id { printf "%s (%s, %s)", $2, $3, $4 }')"
	echo "Deploying to: ${CHOSEN:-$(cat .cue-device) (not connected right now)}"
	echo "Run Scripts/claude-remote.sh --pick to choose another iPhone."
fi

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
