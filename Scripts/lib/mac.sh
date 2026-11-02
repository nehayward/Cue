# Sourced by the Mac scripts. Builds the Cue (Mac) scheme and runs the app
# on this Mac, with its console going to build/mac-console.log.
#
# CUE_MAC_SCHEME and CUE_CONFIGURATION override the scheme and configuration.
# Keep Debug for profiling: Release builds can't be inspected by leaks/heap.

MAC_SCHEME="${CUE_MAC_SCHEME:-Cue (Mac)}"
MAC_CONFIGURATION="${CUE_CONFIGURATION:-Debug}"
# Outside the repo, as Clic's scripts keep it (a checkout in iCloud Drive
# tags files under build/ with xattrs codesign rejects), and apart from
# the iPhone build's.
MAC_DERIVED_DATA="${CUE_MAC_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/Cue-Mac}"
# The console is written outside the repo (`open --stdout` can't redirect into
# iCloud Drive, LaunchServices error -10810, should the checkout ever live
# there); build/mac-console.log links to it.
MAC_CONSOLE_LOG_REAL="$HOME/Library/Logs/Cue-dev/mac-console.log"
MAC_CONSOLE_LOG="build/mac-console.log"

build_mac() {
	local log="build/mac-build.log"
	mkdir -p build
	if ! xcodebuild \
		-project Cue.xcodeproj \
		-scheme "$MAC_SCHEME" \
		-configuration "$MAC_CONFIGURATION" \
		-destination "platform=macOS,variant=Mac Catalyst,arch=$(uname -m)" \
		-derivedDataPath "$MAC_DERIVED_DATA" \
		-allowProvisioningUpdates \
		build >"$log" 2>&1; then
		grep -E "error:|detritus not allowed|^\t[A-Z][A-Za-z]+ .*\(in target" "$log" | sort -u | head -40 >&2 || true
		fail "Build failed. Full log: $log"
	fi
	echo "Build succeeded (log: $log)"
}

# Sets MAC_APP, MAC_EXECUTABLE and MAC_PROCESS for the last build.
find_mac_app() {
	local dir
	MAC_APP=""
	for dir in "$MAC_CONFIGURATION-maccatalyst" "$MAC_CONFIGURATION"; do
		if [ -d "$MAC_DERIVED_DATA/Build/Products/$dir/Cue.app" ]; then
			MAC_APP="$MAC_DERIVED_DATA/Build/Products/$dir/Cue.app"
			break
		fi
	done
	[ -n "$MAC_APP" ] || fail "No Cue.app in $MAC_DERIVED_DATA. Build it with Scripts/deploy-to-mac.sh."
	MAC_PROCESS="$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$MAC_APP/Contents/Info.plist")"
	MAC_EXECUTABLE="$MAC_APP/Contents/MacOS/$MAC_PROCESS"
}

# Quits every running Cue, including an installed copy, so only one runs.
quit_mac_app() {
	pkill -x "$MAC_PROCESS" 2>/dev/null || return 0
	for _ in $(seq 20); do
		pgrep -x "$MAC_PROCESS" >/dev/null || return 0
		sleep 0.25
	done
	pkill -9 -x "$MAC_PROCESS" 2>/dev/null || true
	sleep 0.5
}

# Relaunches the built app. Extra NAME=value arguments are added to its
# environment. Sets MAC_PID. The app keeps running after the script ends.
#
# Launched through LaunchServices only. Running the executable directly and
# then `open`ing the bundle to bring it forward started a second copy whenever
# LaunchServices hadn't seen that build yet (a fresh Release build), and the
# two fought over the Sonos event port, so the survivor found no speakers.
launch_mac_app() {
	quit_mac_app
	mkdir -p build "$(dirname "$MAC_CONSOLE_LOG_REAL")"
	: >"$MAC_CONSOLE_LOG_REAL"
	ln -sfn "$MAC_CONSOLE_LOG_REAL" "$MAC_CONSOLE_LOG"
	# OS_ACTIVITY_DT_MODE sends Logger/os_log output to stderr, as Xcode does.
	local env_args=(--env OS_ACTIVITY_DT_MODE=enable)
	local pair
	for pair in "$@"; do env_args+=(--env "$pair"); done
	open "${env_args[@]}" --stdout "$MAC_CONSOLE_LOG_REAL" --stderr "$MAC_CONSOLE_LOG_REAL" "$MAC_APP" \
		|| fail "Couldn't launch $MAC_APP."
	MAC_PID=""
	for _ in $(seq 40); do
		MAC_PID="$(pgrep -nf "^$MAC_EXECUTABLE" || true)"
		[ -n "$MAC_PID" ] && break
		sleep 0.25
	done
	sleep 1
	if [ -z "$MAC_PID" ] || ! kill -0 "$MAC_PID" 2>/dev/null; then
		tail -40 "$MAC_CONSOLE_LOG" >&2
		fail "Cue exited right after launch."
	fi
}

# Sets MAC_PID to the running Cue, or fails.
running_mac_app() {
	MAC_PID="$(pgrep -nx "$MAC_PROCESS" || true)"
	[ -n "$MAC_PID" ] || fail "Cue is not running on this Mac. Launch it with Scripts/deploy-to-mac.sh."
}
