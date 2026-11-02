#!/bin/bash
# Run the test suite. With only the Command Line Tools installed, swift-build's
# explicit-module scan sometimes leaves out the Swift Testing macro plugin (it lives
# in host/plugins/testing/, one level below the dir that gets scanned), and every
# @Test / #expect then fails with "plugin for module 'TestingMacros' not found".
set -euo pipefail

cd "$(dirname "$0")/.."
plugins="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
if [ -d "$plugins" ]; then
    exec swift test -Xswiftc -plugin-path -Xswiftc "$plugins" "$@"
fi
exec swift test "$@"
