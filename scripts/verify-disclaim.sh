#!/bin/bash
# Check that workflow steps don't inherit Screenshott's Screen Recording grant (#10).
# The app spawns Tools/TCCProbe twice — plainly, then the way workflow steps are
# spawned (responsibility disclaimed) — and logs what CGPreflightScreenCaptureAccess()
# answered in each child. Expect: inherited=true, disclaimed=false. Screenshott needs
# the grant itself for the first answer to mean anything.
#
# Build the app first with scripts/bundle.sh. Screenshott is quit for the check and
# reopened afterwards.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="dist/Screenshott.app"
[[ -d "$APP" ]] || { echo "no $APP — run scripts/bundle.sh first" >&2; exit 1; }
swift build --product TCCProbe
PROBE="$(swift build --show-bin-path)/TCCProbe"

# Launch arguments only reach a fresh process.
if /usr/bin/pgrep -xq Screenshott; then
    /usr/bin/pkill -x Screenshott
    while /usr/bin/pgrep -xq Screenshott; do sleep 0.1; done
fi
LOG="$HOME/Library/Logs/Screenshott.log"
START=$(( $(/usr/bin/wc -l < "$LOG" 2>/dev/null || echo 0) + 1 ))

# Through open, so Screenshott is its own responsible process, as in daily use.
/usr/bin/open "$APP" --args --verify-disclaim "$PROBE"

for _ in $(seq 1 40); do
    if /usr/bin/tail -n "+$START" "$LOG" | /usr/bin/grep -q "verify-disclaim done"; then
        /usr/bin/tail -n "+$START" "$LOG" | /usr/bin/grep "verify-disclaim parent"
        while /usr/bin/pgrep -xq Screenshott; do sleep 0.1; done
        /usr/bin/open "$APP"
        if /usr/bin/tail -n "+$START" "$LOG" | /usr/bin/grep -q "inherited=screenCapture=true disclaimed=screenCapture=false"; then
            echo "PASS: the disclaimed child can't record the screen"
            exit 0
        fi
        echo "FAIL: see the line above" >&2
        exit 1
    fi
    sleep 0.5
done
echo "timed out; last log lines:" >&2
/usr/bin/tail -n 8 "$LOG" >&2
exit 1
