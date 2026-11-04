#!/bin/bash
# Time captures with no input (see Sources/Screenshott/Bench.swift): N rounds of every
# grab path, N ⌘⇧1 full-screen captures and N ⌘⇧2 overlay freezes per path, then
# p50 / p95 per stage in milliseconds.
#
#   scripts/bench.sh [N] [--sample]     # default N = 20: about 2 minutes
#
# --sample also runs `sample` on the app for the whole run (dist/bench/*.sample.txt).
# Sampling every millisecond slows the app, so its timings are not comparable.
#
# Bench captures go to a temp folder that is deleted afterwards and to a private
# pasteboard: nothing lands in ~/Pictures/Screenshott or on the clipboard, and there is
# no shutter sound. The overlay flashes up 3N + 3 times — keep off the keyboard, the
# mouse and the menu bar icon until the summary prints. Whatever Screenshott was
# running before is reopened after.
# Build first with scripts/bundle.sh.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="dist/Screenshott.app"
RUNS=20
SAMPLE=false
for arg in "$@"; do
    case "$arg" in
        --sample) SAMPLE=true ;;
        *) RUNS="$arg" ;;
    esac
done
[[ -d "$APP" ]] || { echo "no $APP — run scripts/bundle.sh first" >&2; exit 1; }
OUT="dist/bench"
mkdir -p "$OUT"
STAMP="$(date +%Y-%m-%d-%H%M%S)"

# Launch arguments only reach a fresh process.
previous=""
if pid="$(/usr/bin/pgrep -x Screenshott)"; then
    exe="$(/bin/ps -o comm= -p "$pid")"
    previous="${exe%/Contents/MacOS/Screenshott}"
    /usr/bin/pkill -x Screenshott
    while /usr/bin/pgrep -xq Screenshott; do sleep 0.1; done
fi
LOG="$HOME/Library/Logs/Screenshott.log"
# Only read what this run writes; earlier runs left their own "done" lines.
START=$(( $(/usr/bin/wc -l < "$LOG" 2>/dev/null || echo 0) + 1 ))

# Through open, not the binary, so Screenshott is its own process for Screen Recording.
/usr/bin/open "$APP" --args --bench "$RUNS"
for _ in $(seq 1 100); do /usr/bin/pgrep -xq Screenshott && break; sleep 0.1; done

if $SAMPLE; then
    /usr/bin/sample Screenshott $(( 6 * RUNS )) -mayDie -file "$OUT/$STAMP.sample.txt" >/dev/null 2>&1 &
fi

status=1
for _ in $(seq 1 $(( 60 + 16 * RUNS ))); do
    if ! /usr/bin/pgrep -xq Screenshott && ! /usr/bin/tail -n "+$START" "$LOG" | /usr/bin/grep -q "bench done"; then
        echo "Screenshott quit before the bench finished (Quit from the menu, or a crash)." >&2
        break
    fi
    if /usr/bin/tail -n "+$START" "$LOG" | /usr/bin/grep -q "bench done"; then
        /usr/bin/tail -n "+$START" "$LOG" | /usr/bin/grep " bench " | /usr/bin/cut -d' ' -f2- | tee "$OUT/$STAMP.txt"
        echo "saved: $OUT/$STAMP.txt"
        status=0
        break
    fi
    sleep 0.5
done
if [[ $status -ne 0 ]]; then
    echo "no summary; last log lines:" >&2
    /usr/bin/tail -n 8 "$LOG" >&2
    /usr/bin/pkill -x Screenshott || true
fi

while /usr/bin/pgrep -xq Screenshott; do sleep 0.1; done
if [[ -n "$previous" && -d "$previous" ]]; then
    /usr/bin/open "$previous"
    echo "reopened $previous"
fi
exit $status
