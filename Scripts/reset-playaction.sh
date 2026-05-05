#!/usr/bin/env bash
set -euo pipefail

# Re-registers the freshly-built Catalyst Clic.app with LaunchServices so
# pkd discovers QueueAction.appex from your Debug-maccatalyst build, instead
# of preferring the App Store / TestFlight copy in /Applications.
#
# Run this after Xcode finishes a Clic (Mac) build.

LSREG="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
DERIVED="$HOME/Library/Developer/Xcode/DerivedData"

echo "==> Locating Debug-maccatalyst Clic.app..."
APP="$(find "$DERIVED" -maxdepth 8 -name "Clic.app" -path '*Debug-maccatalyst*' -print -quit 2>/dev/null || true)"
if [[ -z "${APP:-}" || ! -d "$APP" ]]; then
    echo "    No Debug-maccatalyst Clic.app found in DerivedData."
    echo "    Build the 'Clic (Mac)' scheme in Xcode first (Destination = My Mac (Mac Catalyst))."
    exit 1
fi
echo "    Found: $APP"

APPEX="$APP/Contents/PlugIns/QueueAction.appex"
if [[ ! -d "$APPEX" ]]; then
    echo "==> WARNING: QueueAction.appex not embedded in this build."
    echo "    Make sure the QueueAction target is in the Clic (Mac) scheme's 'Embed App Extensions' phase."
fi

echo "==> Quitting any running Clic..."
killall Clic 2>/dev/null || true

echo "==> Moving any /Applications copy aside (so dev build wins LaunchServices)..."
if [[ -e /Applications/Clic.app ]]; then
    BACKUP="$HOME/Desktop/Clic-installed-$(date +%Y%m%d-%H%M%S).app.bak"
    mv /Applications/Clic.app "$BACKUP"
    echo "    Moved to $BACKUP"
else
    echo "    No /Applications/Clic.app to move."
fi

echo "==> Stripping quarantine..."
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "==> Removing stale plugin registrations..."
pluginkit -mAvvv 2>/dev/null \
    | awk '/^!?\s+com\.nick\.Clic\./ {bundle=$NF} /Path = / && bundle {print $3; bundle=""}' \
    | while read -r path; do
        [[ -n "$path" && "$path" == *.appex ]] || continue
        echo "    -r $path"
        pluginkit -r "$path" 2>/dev/null || true
    done

echo "==> Re-registering fresh build with LaunchServices..."
"$LSREG" -f -v "$APP" >/dev/null

echo "==> Restarting pkd..."
killall pkd 2>/dev/null || true
sleep 2

echo "==> Current Clic plugin registrations:"
pluginkit -mAvvv 2>/dev/null | grep -B1 -A2 -i clic || echo "    (none)"

echo
echo "Done. If QueueAction shows '!' next to its bundle ID, enable it in"
echo "  System Settings -> Login Items & Extensions  (or Privacy & Security -> Extensions)"
echo "Then test by sharing a music link from Safari -> 'Play on Clic'."
