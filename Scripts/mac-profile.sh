#!/bin/bash
# Profile Cue's memory on this Mac.
#
#   Scripts/mac-profile.sh                  # relaunch, sample memory for 120s, then report
#   Scripts/mac-profile.sh 300              # sample for 5 minutes
#   Scripts/mac-profile.sh --stacks         # also record allocation call stacks (slower)
#   Scripts/mac-profile.sh --attach         # profile the Cue that is already running
#   Scripts/mac-profile.sh --interval 0.5   # sample twice a second (default 1)
#   Scripts/mac-profile.sh --trace Allocations 60   # record an Instruments trace instead
#
# Uses the last build from Scripts/deploy-to-mac.sh (Debug; Release builds
# can't be inspected). While it samples, use the app to reproduce the spike.
# Results go to build/profiles/<time>/:
#   memory.csv          footprint and its GPU share over time (seconds, MB, MB, wall clock)
#   cue.memgraph        memory graph at the end; open in Xcode, or run
#                       leaks/heap/vmmap/malloc_history on it again later
#   leaks.txt heap.txt vmmap.txt (and malloc_history.txt with --stacks)
#   console.log         the app's console during the run

set -euo pipefail

cd "$(dirname "$0")/.."

SECONDS_TO_SAMPLE=120
INTERVAL=1
ATTACH=0
STACKS=0
TEMPLATE=""
while [ $# -gt 0 ]; do
	case "$1" in
		--attach) ATTACH=1 ;;
		--stacks) STACKS=1 ;;
		--interval) INTERVAL="${2:?--interval needs seconds}"; shift ;;
		--trace)
			TEMPLATE="${2:?--trace needs an Instruments template, e.g. Allocations, Leaks}"; shift
			SECONDS_TO_SAMPLE=60
			;;
		[0-9]*) SECONDS_TO_SAMPLE="$1" ;;
		*) echo "error: unknown option $1" >&2; exit 1 ;;
	esac
	shift
done

step() { echo -e "\n==== $1 ====\n"; }
fail() { echo "error: $1" >&2; exit 1; }

[ "$(uname)" = "Darwin" ] || fail "Run this on your Mac."
[ "$ATTACH" -eq 1 ] && [ "$STACKS" -eq 1 ] && fail "--stacks needs a fresh launch; drop --attach."

source Scripts/lib/mac.sh
find_mac_app

OUT="build/profiles/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

# Instruments trace: record, then point at the file.
if [ -n "$TEMPLATE" ]; then
	TRACE="$OUT/cue-$(echo "$TEMPLATE" | tr ' ' '-').trace"
	step "Recording $TEMPLATE for ${SECONDS_TO_SAMPLE}s"
	echo "Use the app now to reproduce the problem."
	if [ "$ATTACH" -eq 1 ]; then
		running_mac_app
		TARGET=(--attach "$MAC_PID")
	else
		quit_mac_app
		TARGET=(--launch -- "$MAC_EXECUTABLE")
	fi
	xcrun xctrace record --template "$TEMPLATE" --time-limit "${SECONDS_TO_SAMPLE}s" \
		--output "$TRACE" "${TARGET[@]}" || fail "xctrace failed. Templates: xcrun xctrace list templates"
	step "Done: $TRACE"
	echo "Open it in Instruments: open \"$TRACE\""
	exit 0
fi

if [ "$ATTACH" -eq 1 ]; then
	running_mac_app
	CONSOLE_START="$(wc -l <"$MAC_CONSOLE_LOG" 2>/dev/null || echo 0)"
	step "Profiling running Cue (pid $MAC_PID) for ${SECONDS_TO_SAMPLE}s"
else
	CONSOLE_START=0
	EXTRA_ENV=()
	# Records a call stack for every allocation, so leaks and malloc_history
	# can say where memory came from. Adds memory and CPU overhead.
	[ "$STACKS" -eq 1 ] && EXTRA_ENV=(MallocStackLogging=1)
	step "Launching Cue and profiling for ${SECONDS_TO_SAMPLE}s"
	launch_mac_app "${EXTRA_ENV[@]+"${EXTRA_ENV[@]}"}"
fi
echo "Use the app now to reproduce the memory spike."

# Footprint (Activity Monitor's "Memory" column) and the part of it that is
# GPU memory, as "total,gpu" in MB. vmmap and heap on the memory graph never
# see GPU memory, so spikes that are purely GPU (offscreen rendering, symbol
# and blur animations) only show up in this column.
sample_mb() {
	footprint "$MAC_PID" 2>/dev/null | awk '
		function mb(v, u) { return u == "KB" ? v / 1024 : u == "GB" ? v * 1024 : u == "B" ? v / 1048576 : v }
		/Footprint:/ && !t { for (i = 1; i < NF; i++) if ($i == "Footprint:") t = mb($(i + 1), $(i + 2)) }
		/\(graphics\)$/ { g += mb($1, $2) }
		END { if (t) printf "%.1f,%.1f", t, g }'
}

echo "seconds,footprint_mb,gpu_mb,time" >"$OUT/memory.csv"
START="$(date +%s)"
EXITED=0
while :; do
	NOW="$(date +%s)"
	ELAPSED=$((NOW - START))
	[ "$ELAPSED" -ge "$SECONDS_TO_SAMPLE" ] && break
	kill -0 "$MAC_PID" 2>/dev/null || { EXITED=1; break; }
	SAMPLE="$(sample_mb)"
	if [ -n "$SAMPLE" ]; then
		echo "$ELAPSED,$SAMPLE,$(date +%H:%M:%S)" >>"$OUT/memory.csv"
		printf "\r  %4ss  %8s MB  (GPU %s MB) " "$ELAPSED" "${SAMPLE%,*}" "${SAMPLE#*,}"
	fi
	sleep "$INTERVAL"
done
echo

tail -n +"$((CONSOLE_START + 1))" "$MAC_CONSOLE_LOG" >"$OUT/console.log" 2>/dev/null || true

step "Footprint over time ($OUT/memory.csv)"
awk -F, 'NR > 1 {
		n++; t[n] = $1; m[n] = $2; g[n] = $3; c[n] = $4
		if (n == 1 || $2 > peak) { peak = $2; peakAt = $4 }
		if (n == 1 || $3 > gpeak) { gpeak = $3; gpeakAt = $4 }
	}
	END {
		if (n == 0) { print "  no samples"; exit }
		printf "  start %.0f MB, peak %.0f MB at %s, end %.0f MB (%+.0f MB)\n", m[1], peak, peakAt, m[n], m[n] - m[1]
		printf "  GPU: peak %.0f MB at %s, end %.0f MB (not in vmmap/heap below)\n", gpeak, gpeakAt, g[n]
		print "\n  Biggest jumps between samples:"
		for (i = 2; i <= n; i++) d[i] = m[i] - m[i - 1]
		for (k = 0; k < 8; k++) {
			best = 0
			for (i = 2; i <= n; i++) if (!(i in used) && (best == 0 || d[i] > d[best])) best = i
			if (best == 0 || d[best] < 5) break
			used[best] = 1
			printf "  %s (%ss)  %+.0f MB  -> %.0f MB (GPU %+.0f MB)\n", c[best], t[best], d[best], m[best], g[best] - g[best - 1]
		}
		print "\n  Timeline:"
		step = n > 30 ? int(n / 30) : 1
		for (i = 1; i <= n; i += step) {
			bar = ""; for (j = 0; j < m[i] / peak * 40; j++) bar = bar "#"
			printf "  %s %6.0f MB  GPU %4.0f  %s\n", c[i], m[i], g[i], bar
		}
	}' "$OUT/memory.csv"

if [ "$EXITED" -eq 1 ]; then
	step "Cue exited during profiling; checking for a crash report"
	sleep 3
	Scripts/mac-crashes.sh --since "$START" || true
	exit 1
fi

GRAPH="$OUT/cue.memgraph"
step "Capturing memory graph"
# leaks exits 1 when it finds leaks; that's not a failure here.
leaks --outputGraph="$GRAPH" "$MAC_PID" >/dev/null 2>&1 || true
[ -e "$GRAPH" ] || fail "Couldn't capture a memory graph. Is this a Debug build?"
echo "$GRAPH"

step "Leaks ($OUT/leaks.txt)"
leaks "$GRAPH" >"$OUT/leaks.txt" 2>&1 || true
grep -E "leaks for .* total leaked bytes" "$OUT/leaks.txt" || true
grep -E "ROOT (CYCLE|LEAK)" "$OUT/leaks.txt" | sed -E 's/^ +/  /' | sort | uniq -c | sort -rn | head -20 || true

step "Physical footprint ($OUT/vmmap.txt)"
vmmap --summary "$GRAPH" >"$OUT/vmmap.txt" 2>&1 || true
grep -E "^Physical footprint" "$OUT/vmmap.txt" || true
# Largest memory regions by resident/dirty size.
awk '/^REGION TYPE/ { f = 1 } f && NF' "$OUT/vmmap.txt" | head -30 || true

step "Largest heap object types ($OUT/heap.txt)"
heap -sortBySize "$GRAPH" >"$OUT/heap.txt" 2>&1 || true
awk '/COUNT +BYTES/ { f = 1 } f' "$OUT/heap.txt" | head -30 || true

if [ "$STACKS" -eq 1 ]; then
	step "Live allocations by call stack ($OUT/malloc_history.txt)"
	malloc_history "$GRAPH" -allBySize >"$OUT/malloc_history.txt" 2>&1 || true
	head -60 "$OUT/malloc_history.txt" || true
fi

step "Done: $OUT"
echo "Cue is still running. Open the memory graph in Xcode: open \"$GRAPH\""
