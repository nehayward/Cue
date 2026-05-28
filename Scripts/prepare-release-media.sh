#!/usr/bin/env bash
# Prepare release media for upload to resource.clic.dance/releases/<version>/.
#
# Point at a folder containing raw screen recordings and screenshots — one per
# feature, named with the feature slug used in clic-for-sonos/src/releases.js
# (e.g. share-sheet.mp4, dock-menu.mp4, end-of-song.jpg). The script normalizes
# everything to 720x1280 H.264 (no audio, faststart) + JPG and drops the result
# in a `prepared/` subfolder ready to upload.
#
# Usage:
#   prepare-release-media.sh <folder> [version]
#
# Examples:
#   prepare-release-media.sh ~/Downloads/2026.4
#     reads:   ~/Downloads/2026.4/*.{mp4,mov,jpg,jpeg,png}
#     writes:  ~/Downloads/2026.4/prepared/
#     version: inferred as "2026.4" from the folder name
#
#   prepare-release-media.sh ~/somewhere/random 2026.4
#     overrides the inferred version

set -euo pipefail

SOURCE_DIR="${1:-}"
if [[ -z "$SOURCE_DIR" ]]; then
	echo "usage: $0 <folder> [version]" >&2
	exit 1
fi
if [[ ! -d "$SOURCE_DIR" ]]; then
	echo "source folder not found: $SOURCE_DIR" >&2
	exit 1
fi
if ! command -v ffmpeg >/dev/null 2>&1; then
	echo "ffmpeg is required (brew install ffmpeg)" >&2
	exit 1
fi

SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"
VERSION="${2:-$(basename "$SOURCE_DIR")}"
OUT_DIR="$SOURCE_DIR/prepared"

mkdir -p "$OUT_DIR"

# Scale to fit within 720x1280, preserving the source aspect (no crop). Phone
# screen recordings are taller than 9:16, so cropping would lop the top/bottom
# off the captured UI. The display side uses object-fit: contain and shows the
# card gradient behind any letterbox. fps=30 nearly halves the bitrate vs 60fps
# with no perceptible loss for UI demos. -2 keeps width even (required by H.264).
VIDEO_FILTER="scale='min(720,iw)':'min(1280,ih)':force_original_aspect_ratio=decrease,scale=trunc(iw/2)*2:trunc(ih/2)*2,fps=30"
IMAGE_FILTER="scale='min(720,iw)':'min(1280,ih)':force_original_aspect_ratio=decrease"

echo "==> Preparing release media for $VERSION"
echo "    source: $SOURCE_DIR"
echo "    output: $OUT_DIR"
echo

shopt -s nullglob nocaseglob

video_count=0
for src in "$SOURCE_DIR"/*.mp4 "$SOURCE_DIR"/*.mov; do
	[[ "$src" == "$OUT_DIR/"* ]] && continue
	slug=$(basename "$src")
	slug="${slug%.*}"
	dst="$OUT_DIR/$slug.mp4"
	echo "▶ video: $slug.mp4"
	ffmpeg -y -loglevel error -i "$src" \
		-vf "$VIDEO_FILTER" \
		-c:v libx264 -profile:v high -pix_fmt yuv420p -movflags +faststart \
		-b:v 1200k -maxrate 1500k -bufsize 3000k \
		-an \
		"$dst"
	size=$(du -h "$dst" | cut -f1)
	echo "  → $(basename "$dst") ($size)"
	video_count=$((video_count + 1))
done

image_count=0
for src in "$SOURCE_DIR"/*.jpg "$SOURCE_DIR"/*.jpeg "$SOURCE_DIR"/*.png; do
	[[ "$src" == "$OUT_DIR/"* ]] && continue
	slug=$(basename "$src")
	slug="${slug%.*}"
	dst="$OUT_DIR/$slug.jpg"
	echo "▶ poster: $slug.jpg"
	ffmpeg -y -loglevel error -i "$src" \
		-vf "$IMAGE_FILTER" \
		-q:v 4 \
		"$dst"
	size=$(du -h "$dst" | cut -f1)
	echo "  → $(basename "$dst") ($size)"
	image_count=$((image_count + 1))
done

# OG share card (1200x630 for Reddit / iMessage / Twitter / Discord previews).
# Rendered as SVG then converted to PNG via rsvg-convert. Composites up to 3
# feature phones cascading on the right, version + bullets on the left.
#
# HERO_SLUGS = comma-separated slugs, in "front to back" order (first = most
#              prominent). Falls back to HERO_SLUG, or the first poster.
# BULLETS    = pipe-separated bullet text.
HERO_SLUGS="${HERO_SLUGS:-${HERO_SLUG:-}}"
if [[ -z "$HERO_SLUGS" ]]; then
	for p in "$OUT_DIR"/*.jpg; do
		HERO_SLUGS="$(basename "$p" .jpg)"
		break
	done
fi
BULLETS="${BULLETS:-}"

if [[ -n "$HERO_SLUGS" ]]; then
	if ! command -v rsvg-convert >/dev/null 2>&1; then
		echo "  (skipping og card — rsvg-convert not installed; brew install librsvg)"
	else
		OG_OUT="$OUT_DIR/og.png"
		echo "▶ og card: og.png (heroes=$HERO_SLUGS)"

		# Build cascading phone nodes — front phone first in HERO_SLUGS, rendered
		# last (on top). Each phone sized to 9:19.5 iPhone aspect.
		IFS=',' read -ra SLUGS <<< "$HERO_SLUGS"
		PW=148; PH=320; BZ=8
		BASE_X=624; BASE_Y=155
		STEP_X=180; STEP_Y=0
		PHONE_DEFS=""
		PHONE_NODES=""
		COUNT=${#SLUGS[@]}
		(( COUNT > 3 )) && COUNT=3
		for ((idx = COUNT - 1; idx >= 0; idx--)); do
			slug="${SLUGS[$idx]}"
			poster="$OUT_DIR/$slug.jpg"
			if [[ ! -f "$poster" ]]; then
				echo "  (warning: $slug.jpg not found, skipping)"
				continue
			fi
			b64=$(base64 < "$poster" | tr -d '\n')
			pxe=$((BASE_X + STEP_X * idx))
			pye=$((BASE_Y + STEP_Y * idx))
			bxe=$((pxe - BZ)); bye=$((pye - BZ))
			bwe=$((PW + BZ * 2)); bhe=$((PH + BZ * 2))
			PHONE_DEFS+="<clipPath id=\"sc${idx}\"><rect x=\"$pxe\" y=\"$pye\" width=\"$PW\" height=\"$PH\" rx=\"28\" ry=\"28\"/></clipPath>"
			PHONE_NODES+="<g>"
			PHONE_NODES+="<rect x=\"$bxe\" y=\"$bye\" width=\"$bwe\" height=\"$bhe\" rx=\"34\" ry=\"34\" fill=\"#15191e\" stroke=\"rgba(255,255,255,0.16)\" stroke-width=\"1.5\"/>"
			PHONE_NODES+="<image x=\"$pxe\" y=\"$pye\" width=\"$PW\" height=\"$PH\" xlink:href=\"data:image/jpeg;base64,$b64\" preserveAspectRatio=\"xMidYMid slice\" clip-path=\"url(#sc${idx})\"/>"
			PHONE_NODES+="<rect x=\"$((bxe + 1))\" y=\"$((bye + 1))\" width=\"$((bwe - 2))\" height=\"$((bhe - 2))\" rx=\"33\" ry=\"33\" fill=\"none\" stroke=\"rgba(255,255,255,0.06)\" stroke-width=\"1\"/>"
			PHONE_NODES+="</g>"
		done

		BULLET_SVG=""
		if [[ -n "$BULLETS" ]]; then
			IFS='|' read -ra ITEMS <<< "$BULLETS"
			y=400
			for item in "${ITEMS[@]}"; do
				safe=$(printf '%s' "$item" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g')
				BULLET_SVG+="<g transform=\"translate(95, $y)\"><circle cx=\"0\" cy=\"-9\" r=\"4\" fill=\"#7CDDE8\"/><text x=\"22\" y=\"0\" font-size=\"26\" fill=\"rgba(255,255,255,0.9)\" font-weight=\"500\">${safe}</text></g>"
				y=$((y + 50))
			done
		fi

		SVG_FILE="$OUT_DIR/og.svg"
		cat > "$SVG_FILE" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1200" height="630" viewBox="0 0 1200 630">
	<defs>
		<radialGradient id="gTL" cx="0" cy="0" r="700" gradientUnits="userSpaceOnUse">
			<stop offset="0%" stop-color="#5AADC4" stop-opacity="0.32"/>
			<stop offset="55%" stop-color="#5AADC4" stop-opacity="0"/>
		</radialGradient>
		<radialGradient id="gBR" cx="1200" cy="630" r="720" gradientUnits="userSpaceOnUse">
			<stop offset="0%" stop-color="#5AADC4" stop-opacity="0.22"/>
			<stop offset="55%" stop-color="#5AADC4" stop-opacity="0"/>
		</radialGradient>
		<radialGradient id="gBL" cx="0" cy="630" r="520" gradientUnits="userSpaceOnUse">
			<stop offset="0%" stop-color="#285A82" stop-opacity="0.3"/>
			<stop offset="60%" stop-color="#285A82" stop-opacity="0"/>
		</radialGradient>
		<radialGradient id="gTR" cx="1200" cy="0" r="500" gradientUnits="userSpaceOnUse">
			<stop offset="0%" stop-color="#4899AD" stop-opacity="0.14"/>
			<stop offset="60%" stop-color="#4899AD" stop-opacity="0"/>
		</radialGradient>
		<radialGradient id="gCenter" cx="600" cy="315" r="500" gradientUnits="userSpaceOnUse">
			<stop offset="0%" stop-color="#000" stop-opacity="0.45"/>
			<stop offset="75%" stop-color="#000" stop-opacity="0"/>
		</radialGradient>
		$PHONE_DEFS
	</defs>

	<rect width="1200" height="630" fill="#060606"/>
	<rect width="1200" height="630" fill="url(#gTL)"/>
	<rect width="1200" height="630" fill="url(#gBR)"/>
	<rect width="1200" height="630" fill="url(#gBL)"/>
	<rect width="1200" height="630" fill="url(#gTR)"/>
	<rect width="1200" height="630" fill="url(#gCenter)"/>

	$PHONE_NODES

	<g font-family="SF Pro Rounded, ui-rounded, -apple-system, system-ui, Helvetica, sans-serif">
		<text x="90" y="140" font-size="22" letter-spacing="4" font-weight="700" fill="#7CDDE8">WHAT'S NEW</text>
		<text x="90" y="280" font-size="132" font-weight="700" fill="white">$VERSION</text>
		$BULLET_SVG
	</g>
</svg>
EOF

		rsvg-convert -w 1200 -h 630 "$SVG_FILE" -o "$OG_OUT"
		rm -f "$SVG_FILE"
		size=$(du -h "$OG_OUT" | cut -f1)
		echo "  → og.png ($size)"
	fi
fi

echo
echo "==> Done. ${video_count} video(s), ${image_count} image(s)."
echo "    Upload contents of:"
echo "        $OUT_DIR/"
echo "    to:"
echo "        https://resource.clic.dance/releases/$VERSION/"
