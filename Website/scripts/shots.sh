#!/usr/bin/env bash
# The site's screenshots from the raw captures in build/website/raw. Capture
# them with Tools/StoreShots and the site's own project, which leaves covers
# unblurred (the App Store's project blurs them):
#
#   swift run -c release --package-path Tools/StoreShots storeshots \
#       shoot Marketing/Website/storeshots.json iphone now-playing [--launch]
#
# Each iPhone capture becomes public/shots/<name>.jpg (1150 px tall, for the
# pages) and public/press/cue-<name>.jpg (full size, for the press kit); each
# watch capture goes to both at its full 416 × 496.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RAW="$ROOT/build/website/raw"
SITE="$ROOT/Website/public"

for shot in "$RAW"/iphone/*.png; do
	[[ -e "$shot" ]] || continue
	name="$(basename "$shot" .png)"
	sips -s format jpeg -s formatOptions 82 --resampleHeight 1150 "$shot" --out "$SITE/shots/$name.jpg" >/dev/null
	sips -s format jpeg -s formatOptions 88 "$shot" --out "$SITE/press/cue-$name.jpg" >/dev/null
	echo "shots/$name.jpg, press/cue-$name.jpg"
done

for shot in "$RAW"/watch/*.png; do
	[[ -e "$shot" ]] || continue
	name="$(basename "$shot" .png)"
	sips -s format jpeg -s formatOptions 86 "$shot" --out "$SITE/shots/$name.jpg" >/dev/null
	cp "$SITE/shots/$name.jpg" "$SITE/press/cue-$name.jpg"
	echo "shots/$name.jpg, press/cue-$name.jpg"
done
