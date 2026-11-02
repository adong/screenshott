#!/bin/bash
# Build dist/Screenshott.app from the SwiftPM product and sign it.
#
#   scripts/bundle.sh            # release build
#   scripts/bundle.sh debug      # debug build
#
# Signing identity: $SCREENSHOTT_SIGN_IDENTITY, else "Screenshott Dev", else the first
# code-signing identity in the keychain. Ad-hoc signing is the last resort and is loud
# about it: TCC keys an ad-hoc app to its CDHash, which changes on every build, so the
# Screen Recording grant silently lapses each time.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
APP="dist/Screenshott.app"

swift build -c "$CONFIG" --product Screenshott
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

# Replacing the bundle under a running instance leaves the old code running, and a
# later `open` just activates it — so a rebuild would silently test the old build.
# Quit it first and reopen at the end.
was_running=false
if /usr/bin/pgrep -xq Screenshott; then
    was_running=true
    /usr/bin/pkill -x Screenshott
    while /usr/bin/pgrep -xq Screenshott; do sleep 0.1; done
fi

if [ -e "$APP" ]; then find "$APP" -delete; fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Screenshott" "$APP/Contents/MacOS/Screenshott"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
/usr/bin/plutil -lint -s "$APP/Contents/Info.plist"

identities="$(/usr/bin/security find-identity -p codesigning 2>/dev/null || true)"
identity="${SCREENSHOTT_SIGN_IDENTITY:-}"
if [ -z "$identity" ] && grep -q '"Screenshott Dev"' <<<"$identities"; then
    identity="Screenshott Dev"
fi
if [ -z "$identity" ]; then
    # Self-signed certs may carry a trailing "(CSSMERR_TP_NOT_TRUSTED)"; codesign still
    # accepts them, so match the quoted name and ignore whatever follows.
    identity="$(sed -n 's/^ *[0-9]*) [0-9A-F]\{40\} "\([^"]*\)".*$/\1/p' <<<"$identities" | head -1)"
fi

if [ -n "$identity" ]; then
    /usr/bin/codesign --force --options runtime --sign "$identity" "$APP"
    echo "signed with: $identity"
else
    /usr/bin/codesign --force --sign - "$APP"
    echo "WARNING: no code-signing identity found, signed ad-hoc." >&2
    echo "         Screen Recording permission will reset on every rebuild." >&2
fi

/usr/bin/codesign --verify --strict "$APP"
echo "built: $PWD/$APP"

if $was_running; then
    /usr/bin/open "$APP"
    echo "reopened Screenshott (the previous instance was quit before the rebuild)"
fi
