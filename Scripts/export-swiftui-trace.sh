#!/bin/bash
# Exports the useful parts of an Instruments SwiftUI trace into a small zip
# that can be shared for review, since a .trace bundle can only be read in
# Instruments.
#
# Usage: Scripts/export-swiftui-trace.sh path/to/Clic.trace [--raw] [--run N]
#
# A .trace can hold several recordings ("runs"); the latest is exported
# unless --run picks another.
#
# Writes <trace name>-export/ next to the trace and zips it. The zip holds:
#   summary.txt   Per table: row count, the most frequent values in each
#                 column (which views updated, and why), and a per-second
#                 timeline of how many updates happened. Usually all that's
#                 needed. Also printed to the terminal.
#   *.xml         The small tables (life cycle, hitches, hangs) in full.
# With --raw, the large tables are included too, cut to 5 MB each.
#
# ASCII only: macOS ships bash 3.2, which can read a multi-byte character
# after a variable name as part of the name.

set -uo pipefail

TRACE="${1:-}"
shift || true
RAW=""
RUN=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --raw) RAW="--raw" ;;
        --run) RUN="${2:-}"; shift ;;
    esac
    shift
done
if [[ -z "${TRACE}" || ! -e "${TRACE}" ]]; then
    echo "Usage: $0 path/to/file.trace [--raw] [--run N]" >&2
    exit 1
fi

NAME="$(basename "${TRACE%.trace}")"
PARENT="$(cd "$(dirname "${TRACE}")" && pwd)"
OUT="${PARENT}/${NAME}-export"
ZIP="${PARENT}/${NAME}-export.zip"
RAW_MAX_BYTES=5000000
TABLES=(swiftui-updates swiftui-causes life-cycle-period hitches potential-hangs)
SMALL_TABLES=" life-cycle-period hitches potential-hangs "

rm -rf "${OUT}"
mkdir -p "${OUT}/full"

xcrun xctrace export --input "${TRACE}" --toc > "${OUT}/full/toc.txt"
RUNS="$(grep -o '<run number="[0-9]*"' "${OUT}/full/toc.txt" | grep -o '[0-9]*' | tr '\n' ' ')"
if [[ -z "${RUN}" ]]; then
    RUN="$(echo "${RUNS}" | tr ' ' '\n' | grep . | sort -n | tail -1)"
fi
echo "Runs in this trace: ${RUNS:-none found}- exporting run ${RUN:-1}"
RUN="${RUN:-1}"

for schema in "${TABLES[@]}"; do
    echo "Exporting ${schema}..."
    if ! xcrun xctrace export --input "${TRACE}" \
        --xpath "/trace-toc/run[@number=\"${RUN}\"]/data/table[@schema=\"${schema}\"]" \
        > "${OUT}/full/${schema}.xml" 2> "${OUT}/full/${schema}.err"; then
        echo "  not in this trace, skipped"
        rm -f "${OUT}/full/${schema}.xml"
    fi
    rm -f "${OUT}/full/${schema}.err"
done

echo "Summarising (streams the files, so large traces take a minute)..."
if ! /usr/bin/env python3 - "${OUT}/full" "${OUT}/summary.txt" <<'PY'
import collections, os, sys
import xml.etree.ElementTree as ET

source, destination = sys.argv[1], sys.argv[2]
lines = []

for file in sorted(f for f in os.listdir(source) if f.endswith(".xml")):
    schema = file[: -len(".xml")]
    path = os.path.join(source, file)
    lines.append(f"==== {schema} ({os.path.getsize(path) / 1e6:.1f} MB)")

    # xctrace writes each value once with an id and refers back to it after,
    # so remember every id's text while streaming.
    values = {}
    columns = []
    row_count = 0
    counters = collections.defaultdict(collections.Counter)
    per_second = collections.Counter()
    # For SwiftUI updates: what updated, and why, second by second - the
    # overall top values can't say which phase of the recording they're from.
    second_detail = collections.defaultdict(lambda: collections.defaultdict(collections.Counter))
    detail_columns = ("description", "root-causes")
    first_rows = []

    def text_of(el):
        ref = el.get("ref")
        if ref is not None:
            return values.get(ref, "")
        text = (el.get("fmt") or (el.text or "")).strip()
        if el.get("id") is not None:
            values[el.get("id")] = text
        return text

    def raw_of(el):
        ref = el.get("ref")
        return raw_values.get(ref) if ref is not None else (el.text or "").strip()

    raw_values = {}

    try:
        for event, el in ET.iterparse(path, events=("end",)):
            if el.tag == "col":
                columns.append(el.findtext("mnemonic") or el.findtext("name") or "?")
            elif el.tag == "row":
                row_count += 1
                cells = list(el)
                texts = []
                for index, cell in enumerate(cells):
                    # Nested values (a backtrace, a struct) still register their
                    # ids for later refs.
                    for inner in cell.iter():
                        if inner is not cell and inner.get("id") is not None:
                            text_of(inner)
                    if cell.get("id") is not None:
                        raw_values[cell.get("id")] = (cell.text or "").strip()
                    text = text_of(cell)
                    texts.append(text)
                    name = columns[index] if index < len(columns) else cell.tag
                    if text:
                        counters[name][text[:160]] += 1
                # The first column is the start time, in nanoseconds.
                second = None
                if cells:
                    try:
                        second = int(raw_of(cells[0]) or "") // 1_000_000_000
                        per_second[second] += 1
                    except ValueError:
                        pass
                if second is not None and schema == "swiftui-updates":
                    for index, text in enumerate(texts):
                        if index < len(columns) and columns[index] in detail_columns and text:
                            second_detail[second][columns[index]][text[:110]] += 1
                if len(first_rows) < 300:
                    first_rows.append(" | ".join(texts))
                el.clear()
    except ET.ParseError as error:
        lines.append(f"  stopped early, could not parse further: {error}")

    lines.append(f"  rows: {row_count}")
    lines.append(f"  columns: {', '.join(columns)}")

    for name, counter in counters.items():
        # Timestamps and durations are near-unique and say nothing as a
        # frequency table.
        if row_count > 50 and len(counter) > 0.9 * row_count:
            continue
        lines.append(f"  -- {name}: top values")
        for text, count in counter.most_common(30):
            lines.append(f"     {count:8d}  {text}")

    if per_second and schema.startswith("swiftui"):
        lines.append("  -- rows per second of the recording")
        for second in range(min(per_second), max(per_second) + 1):
            count = per_second.get(second, 0)
            lines.append(f"     {second:4d}s {count:7d} {'#' * min(count // 20, 60)}")

    if second_detail:
        lines.append("  -- each second: top updates and their causes")
        for second in sorted(second_detail):
            lines.append(f"     {second:4d}s ({per_second.get(second, 0)} updates)")
            for name in detail_columns:
                for text, count in second_detail[second][name].most_common(4):
                    lines.append(f"        {name[:5]} {count:6d}  {text}")

    if schema in ("life-cycle-period", "potential-hangs", "hitches"):
        lines.append("  -- every row (up to 300)")
        lines.extend("     " + row for row in first_rows)
    lines.append("")

with open(destination, "w") as handle:
    handle.write("\n".join(lines))
PY
then
    echo "Summary failed - see the error above. Send that output instead." >&2
fi

echo "run ${RUN} of: ${RUNS}" > "${OUT}/run.txt"

# Hangs: what the main thread was doing during each one, from the Time
# Profiler samples. Only exported when there are hangs - the table is huge.
if [[ -s "${OUT}/full/potential-hangs.xml" ]] && grep -q "<row>" "${OUT}/full/potential-hangs.xml"; then
    echo "Exporting time-profile for the hangs (large, takes a while)..."
    if xcrun xctrace export --input "${TRACE}" \
        --xpath "/trace-toc/run[@number=\"${RUN}\"]/data/table[@schema=\"time-profile\"]" \
        > "${OUT}/full/time-profile.xml" 2> /dev/null; then
        echo "Summarising the hangs..."
        if ! /usr/bin/env python3 - "${OUT}/full/potential-hangs.xml" "${OUT}/full/time-profile.xml" >> "${OUT}/summary.txt" <<'PY'
import collections, sys
import xml.etree.ElementTree as ET

hangs_path, profile_path = sys.argv[1], sys.argv[2]

# Hang windows, in nanoseconds. Refs point back at earlier values by id.
windows = []
ids = {}
for row in ET.parse(hangs_path).getroot().iter("row"):
    cells = list(row)
    def raw(cell):
        if cell.get("ref") is not None:
            return ids.get(cell.get("ref"), "")
        if cell.get("id") is not None:
            ids[cell.get("id")] = (cell.text or "").strip()
        return (cell.text or "").strip()
    start, duration = int(raw(cells[0])), int(raw(cells[1]))
    windows.append((start, start + duration))

frame_names = {}      # frame id -> name
backtraces = {}       # (tagged-)backtrace id -> [frame names], innermost first
threads = {}          # thread id -> display name
seen = collections.Counter()   # for diagnosing a run that matches nothing
per_hang = [dict(samples=0, leaf=collections.Counter(), inclusive=collections.Counter(),
                 stacks=collections.Counter()) for _ in windows]

def frame_name(frame):
    if frame.get("ref") is not None:
        return frame_names.get(frame.get("ref"), "?")
    name = frame.get("name") or frame.get("addr") or "?"
    if frame.get("id") is not None:
        frame_names[frame.get("id")] = name
    return name

def stack_of(backtrace):
    # Newer xctrace wraps the stack in <tagged-backtrace>; either can be a ref.
    if backtrace.get("ref") is not None:
        return backtraces.get(backtrace.get("ref"), [])
    frames = [frame_name(frame) for frame in backtrace.iter("frame")]
    if backtrace.get("id") is not None:
        backtraces[backtrace.get("id")] = frames
    for inner in backtrace.iter("backtrace"):
        if inner is not backtrace and inner.get("id") is not None:
            backtraces[inner.get("id")] = frames
    return frames

def thread_name(thread):
    if thread.get("ref") is not None:
        return threads.get(thread.get("ref"), "")
    name = thread.get("fmt") or ""
    if thread.get("id") is not None:
        threads[thread.get("id")] = name
    return name

for event, el in ET.iterparse(profile_path, events=("end",)):
    if el.tag != "row":
        continue
    time = thread = stack = None
    seen["rows"] += 1
    if seen["rows"] == 1:
        seen["first row: " + ", ".join(cell.tag for cell in el)] += 1
    for cell in el:
        if cell.tag == "sample-time":
            ref = cell.get("ref")
            text = ids.get(ref) if ref is not None else (cell.text or "").strip()
            if cell.get("id") is not None:
                ids[cell.get("id")] = text
            time = int(text) if text else None
        elif cell.tag == "thread":
            thread = thread_name(cell)
        elif cell.tag in ("backtrace", "tagged-backtrace"):
            stack = stack_of(cell)
    el.clear()
    if time is None or stack is None:
        seen["rows without a time or stack"] += 1
        continue
    if "Main Thread" not in (thread or ""):
        continue
    seen["main thread rows"] += 1
    for index, (start, end) in enumerate(windows):
        if start <= time <= end:
            hang = per_hang[index]
            hang["samples"] += 1
            hang["leaf"][stack[0] if stack else "?"] += 1
            for name in set(stack):
                hang["inclusive"][name] += 1
            hang["stacks"][" <- ".join(stack[:18])] += 1

print("==== main thread during each hang (Time Profiler samples)")
for (start, end), hang in zip(windows, per_hang):
    print(f"  -- hang at {start / 1e9:.3f}s for {(end - start) / 1e6:.0f} ms: {hang['samples']} samples")
    print("     where time was spent (innermost frame):")
    for name, count in hang["leaf"].most_common(15):
        print(f"       {count:6d}  {name[:150]}")
    print("     on the stack (inclusive):")
    for name, count in hang["inclusive"].most_common(40):
        print(f"       {count:6d}  {name[:150]}")
    print("     most common stacks:")
    for stack, count in hang["stacks"].most_common(6):
        print(f"       {count:6d}  {stack[:1500]}")
    print("")
if not any(hang["samples"] for hang in per_hang):
    print("  no samples matched - what the parser saw:")
    for name, count in seen.items():
        print(f"     {count:8d}  {name}")
    print(f"     hang windows (ns): {windows}")
PY
        then
            echo "Hang summary failed - see the error above." >&2
        fi
    else
        echo "  no time-profile in this trace, skipped"
    fi
fi

# The zip: the summary, the small tables, and (with --raw) the large ones cut
# short.
for full in "${OUT}"/full/*.xml; do
    [[ -e "${full}" ]] || continue
    schema="$(basename "${full}" .xml)"
    if [[ "${SMALL_TABLES}" == *" ${schema} "* ]]; then
        cp "${full}" "${OUT}/${schema}.xml"
    elif [[ "${RAW}" == "--raw" ]]; then
        head -c "${RAW_MAX_BYTES}" "${full}" > "${OUT}/${schema}.partial.xml"
    fi
done

rm -f "${ZIP}"
(cd "${OUT}" && zip -qr9 "${ZIP}" . -x "full/*")

echo
if [[ -s "${OUT}/summary.txt" ]]; then
    cat "${OUT}/summary.txt"
    echo
fi
echo "Done: ${ZIP} ($(du -h "${ZIP}" | cut -f1))"
echo "Send the zip, or paste the summary above."
