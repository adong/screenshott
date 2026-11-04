#!/bin/bash
# Drive Delayed Area, Repeat Last Area and the example workflows in the built app, with
# no mouse (see Sources/Screenshott/SelfTest.swift), and print PASS / FAIL per check.
# Install the examples first: scripts/pack-workflows.sh, then double-click
# dist/workflows/copy-markdown-link.screenshottworkflow and half-size.screenshottworkflow.
#
# Side effects: the shutter sound, the clipboard, and a few captures of a stock
# wallpaper in ~/Pictures/Screenshott. Screenshott is quit for the run and reopened
# afterwards. Build first with scripts/bundle.sh.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="dist/Screenshott.app"
[[ -d "$APP" ]] || { echo "no $APP — run scripts/bundle.sh first" >&2; exit 1; }

# Launch arguments only reach a fresh process.
if /usr/bin/pgrep -xq Screenshott; then
    /usr/bin/pkill -x Screenshott
    while /usr/bin/pgrep -xq Screenshott; do sleep 0.1; done
fi
LOG="$HOME/Library/Logs/Screenshott.log"
START=$(( $(/usr/bin/wc -l < "$LOG" 2>/dev/null || echo 0) + 1 ))

# Through open, not the binary, so Screenshott is its own process for Screen Recording.
/usr/bin/open "$APP" --args --self-test

for _ in $(seq 1 80); do
    if /usr/bin/tail -n "+$START" "$LOG" | /usr/bin/grep -q "self-test done"; then
        /usr/bin/tail -n "+$START" "$LOG" | /usr/bin/grep -E "self-test|workflow .* failed"
        while /usr/bin/pgrep -xq Screenshott; do sleep 0.1; done
        /usr/bin/open "$APP"
        /usr/bin/tail -n "+$START" "$LOG" | /usr/bin/grep -q "self-test done, 0 failed"
        exit $?
    fi
    sleep 0.5
done
echo "timed out; last log lines:" >&2
/usr/bin/tail -n 8 "$LOG" >&2
exit 1
