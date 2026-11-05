#!/bin/bash
# Could Cue (Mac) download Apple Music songs by asking the Music app, as it
# deletes playlists (ApplePlaylistDeleter)? MusicKit can't download.
#
#   Scripts/check-music-download.sh          # what Music's dictionary allows
#   Scripts/check-music-download.sh --try    # and download the songs selected in Music
#
# The first part answers whether a sandboxed Cue may send `download` at all:
# Music checks each event against the access groups in Cue's
# scripting-targets (Mac/Cue-Mac.entitlements), so the command has to be in
# one of them, or in one Cue could add. It also prints the event's code,
# which MusicLibraryScripter's raw Apple events would need.
#
# --try runs from Terminal, which isn't sandboxed, so it only shows whether
# Music downloads an Apple Music (subscription) song when asked, and what
# the song looks like to a script before and after. Select one or more songs
# in Music that aren't downloaded, then run it. macOS asks once whether
# Terminal may control Music.

set -euo pipefail

cd "$(dirname "$0")/.."

fail() { echo "error: $1" >&2; exit 1; }

MUSIC=/System/Applications/Music.app
ENTITLEMENTS=Mac/Cue-Mac.entitlements

[[ -d $MUSIC ]] || fail "no Music app at $MUSIC"

try=false
case "${1:-}" in
    --try) try=true ;;
    "") ;;
    *) fail "unknown option $1 (use --try)" ;;
esac

SDEF=$(mktemp "${TMPDIR:-/tmp}/music-sdef.XXXXXX")
trap 'rm -f "$SDEF"' EXIT
sdef "$MUSIC" > "$SDEF"

xpath() { xmllint --xpath "$1" "$SDEF" 2>/dev/null || true; }

echo "Music $(defaults read "$MUSIC/Contents/Info" CFBundleShortVersionString) on macOS $(sw_vers -productVersion)"
echo

command=$(xpath '//command[@name="download"]')
[[ -n $command ]] || fail "Music's dictionary has no download command"

echo "Music's download command:"
echo "$command"
echo

code=$(xpath 'string(//command[@name="download"]/@code)')
echo "Event code: ${code:-none} (class ${code:0:4}, id ${code:4:4})"

# Identifiers of the access groups an XPath names, one a line, sorted.
identifiers() {
    xpath "$1" | grep -o 'identifier="[^"]*"' | sed 's/identifier="\(.*\)"/\1/' | sort -u || true
}

groups=$(identifiers '//command[@name="download"]/access-group/@identifier')
suite_groups=$(identifiers '//suite[command[@name="download"]]/access-group/@identifier')
all_groups=$(identifiers '//access-group/@identifier')
cue_groups=$(grep -o 'com\.apple\.Music\.[A-Za-z.-]*' "$ENTITLEMENTS" | sort -u || true)

line() { echo ${1:-none}; }
echo "download's own access groups: $(line "$groups")"
echo "Its suite's access groups: $(line "$suite_groups")"
echo "Cue's scripting-targets for Music: $(line "$cue_groups")"
echo "Every access group Music declares: $(line "$all_groups")"
echo

shared() { comm -12 <(echo "$1") <(echo "$cue_groups") | grep -q .; }

if [[ -n $groups ]]; then
    if shared "$groups"; then
        echo "Verdict: Cue's entitlements already cover download."
    else
        echo "Verdict: Cue would need one of $(line "$groups") added to its"
        echo "scripting-targets for com.apple.Music in $ENTITLEMENTS."
    fi
elif [[ -n $suite_groups ]]; then
    echo "Verdict: download has no access group of its own; its suite declares"
    echo "$(line "$suite_groups"), which may or may not cover it. Only sending it from"
    echo "Cue will tell (Music answers -10004 or -1743 if it's refused)."
else
    echo "Verdict: download is in no access group, so a sandboxed Cue can't send it"
    echo "through scripting-targets. It would take"
    echo "com.apple.security.temporary-exception.apple-events for com.apple.Music,"
    echo "which App Review rarely accepts."
fi

$try || exit 0

echo
echo "Downloading the songs selected in Music…"
osascript - <<'APPLESCRIPT' 2>&1
on run
	tell application "Music"
		set picked to selection
		if (count of picked) is 0 then error "Select one or more Apple Music songs in Music first, ones not downloaded yet." number 1
		set ids to {}
		repeat with t in picked
			set end of ids to persistent ID of t
		end repeat
	end tell

	log "Before:"
	my report(ids)

	repeat with pid in ids
		set theID to contents of pid
		try
			tell application "Music"
				set t to first track of library playlist 1 whose persistent ID is theID
				download t
			end tell
			log "download " & theID & ": sent"
		on error errText number errNum
			log "download " & theID & ": error " & errNum & " " & errText
		end try
	end repeat

	repeat with pass from 1 to 6
		delay 10
		log "After " & (pass * 10) & " s:"
		my report(ids)
	end repeat
	return
end run

on report(ids)
	repeat with pid in ids
		log "  " & my describe(contents of pid)
	end repeat
end report

-- Name, class, cloud status and file, as a script sees the track.
on describe(pid)
	set f to missing value
	tell application "Music"
		try
			set t to first track of library playlist 1 whose persistent ID is pid
		on error
			return pid & ": not in the library"
		end try
		set msg to pid & " " & (name of t) & ": " & ((class of t) as text) & ", cloud status " & ((cloud status of t) as text)
		try
			set f to location of t
		end try
	end tell
	if f is not missing value then
		set msg to msg & ", file " & (POSIX path of f)
	else
		set msg to msg & ", no file"
	end if
	return msg
end describe
APPLESCRIPT

echo
echo "Now check Music shows them as downloaded, turn Wi-Fi off and play one in Cue (Mac)."
