#!/bin/bash
# Photograph the area overlay, the thumbnail, Settings (Presets and Workflows) and the editor for the README,
# driving the real app without a mouse (see Sources/Screenshott/ReadmeShots.swift).
# Writes PNGs already cropped for docs/images, shot over a stock wallpaper.
#
#   scripts/readme-shots.sh [out-dir]     # default: dist/readme-shots
#
# Side effects, same as one real ⌘⇧2 + Enter: the shutter sound, the clipboard is
# replaced, and one capture is saved to ~/Pictures/Screenshott. Build first with
# scripts/bundle.sh.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="dist/Screenshott.app"
OUT="${1:-dist/readme-shots}"
[[ -d "$APP" ]] || { echo "no $APP — run scripts/bundle.sh first" >&2; exit 1; }
# A screen saver draws above every window, the backdrop included, so the shots would
# show it instead (2026-11-03: a flip clock).
if /usr/bin/pgrep -xq ScreenSaverEngine || /usr/bin/pgrep -xq legacyScreenSaver; then
    echo "a screen saver is running — wake the screen and run again" >&2
    exit 1
fi
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

# Launch arguments only reach a fresh process.
if /usr/bin/pgrep -xq Screenshott; then
    /usr/bin/pkill -x Screenshott
    while /usr/bin/pgrep -xq Screenshott; do sleep 0.1; done
fi
LOG="$HOME/Library/Logs/Screenshott.log"
# Only read what this run writes; earlier runs left their own "done" lines.
START=$(( $(/usr/bin/wc -l < "$LOG" 2>/dev/null || echo 0) + 1 ))

# Through open, not the binary, so Screenshott is its own process for Screen Recording.
/usr/bin/open "$APP" --args --readme-shots "$OUT"

for _ in $(seq 1 30); do
    if /usr/bin/tail -n "+$START" "$LOG" | /usr/bin/grep -q "readme-shots done"; then
        /usr/bin/tail -n "+$START" "$LOG" | /usr/bin/grep "readme-shots"
        exit 0
    fi
    sleep 0.5
done
echo "timed out; last log lines:" >&2
/usr/bin/tail -n 8 "$LOG" >&2
exit 1
