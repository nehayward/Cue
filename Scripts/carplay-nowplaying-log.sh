#!/bin/bash
# Which of Cue's two Now Playing cards the car's Now Playing read, from the
# phone's own system log. Cue has two in MediaRemote: its own process's
# (`dance.cue(<pid>) > default`, the stream player's: Plex, Subsonic, Files,
# TuneIn, books) and MusicKit's player for Apple Music, published from
# com.apple.MediaPlayer.RemotePlayerService. On iOS 27 CarPlay's template
# host (CarPlayTemplateUIHost) stays on one of them (FB24840951). This shows
# mediaremoted's lines naming the template host or RemotePlayerService beside
# Cue's own hand-offs (localplayback, carplay, nowplaying).
#
#   Scripts/carplay-nowplaying-log.sh          # the last 15 minutes
#   Scripts/carplay-nowplaying-log.sh 40m      # the last 40
#
# Reproduce first, in the car or in Xcode's CarPlay Simulator with the phone
# on USB (Apple Music, then a book), then run this within the window with the
# phone plugged in. It asks for your password (log collect needs sudo). The
# archive and the filtered lines land in build/carplay-nowplaying.

set -euo pipefail

cd "$(dirname "$0")/.."

SINCE="${1:-15m}"
OUT="build/carplay-nowplaying"

fail() { echo "error: $1" >&2; exit 1; }

source Scripts/lib/iphone.sh
resolve_iphone

rm -rf "$OUT"
mkdir -p "$OUT"
echo "Collecting the last $SINCE of $NAME's log (sudo)"
sudo log collect --device-udid "$UDID" --last "$SINCE" --output "$OUT/phone.logarchive" >/dev/null \
	|| fail "Couldn't collect the log. Is the phone plugged in, unlocked and trusting this Mac?"
sudo chown -R "$(id -un)" "$OUT"

log show --archive "$OUT/phone.logarchive" --style compact --info --debug --predicate '
	(process == "mediaremoted" AND (eventMessage CONTAINS "CarPlayTemplateUIHost" OR eventMessage CONTAINS "RemotePlayerService"))
	OR (subsystem == "dance.cue" AND category IN {"localplayback", "carplay", "nowplaying"})
' > "$OUT/nowplaying.log"

echo "$(wc -l < "$OUT/nowplaying.log" | tr -d ' ') lines in $OUT/nowplaying.log"
echo "==== what the template host asked for ===="
grep "CarPlayTemplateUIHost" "$OUT/nowplaying.log" | tail -n 40 || echo "(nothing from CarPlayTemplateUIHost)"
echo "==== Cue's hand-offs ===="
grep -E "dance\.cue" "$OUT/nowplaying.log" | grep -v mediaremoted | tail -n 40 || true
