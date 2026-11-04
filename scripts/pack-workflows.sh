#!/bin/bash
# Zip each example in Examples/Workflows into a double-clickable .screenshottworkflow.
#
#   scripts/pack-workflows.sh [out-dir]     # default: dist/workflows
#
# Double-click one (with Screenshott built and run once, so macOS knows the type) to
# install it after a confirmation that lists every step it runs.
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="${1:-dist/workflows}"
mkdir -p "$OUT"
for dir in Examples/Workflows/*/; do
    name="$(basename "$dir")"
    target="$OUT/$name.screenshottworkflow"
    rm -f "$target"
    # workflow.json at the top of the zip; no resource forks, xattrs or quarantine.
    /usr/bin/ditto -c -k --norsrc --noextattr --noqtn --noacl "$dir" "$target"
    echo "packed: $target"
done
