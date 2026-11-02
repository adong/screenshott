#!/bin/bash
# Redraw Support/AppIcon.icns from the vector drawing code in Tools/MakeIcon.
set -euo pipefail

cd "$(dirname "$0")/.."
swift build --product MakeIcon
"$(swift build --show-bin-path)/MakeIcon" Support/AppIcon.iconset
/usr/bin/iconutil -c icns Support/AppIcon.iconset -o Support/AppIcon.icns
echo "wrote Support/AppIcon.icns"
