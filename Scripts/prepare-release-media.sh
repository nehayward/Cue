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

echo
echo "==> Done. ${video_count} video(s), ${image_count} image(s)."
echo "    Upload contents of:"
echo "        $OUT_DIR/"
echo "    to:"
echo "        https://resource.clic.dance/releases/$VERSION/"
