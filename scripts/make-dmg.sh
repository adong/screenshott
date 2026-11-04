#!/bin/bash
# Package dist/Screenshott.app into dist/Screenshott-<version>.dmg for a GitHub release.
#
#   scripts/bundle.sh && scripts/make-dmg.sh
#
# The disk image holds the app, a link to /Applications, the example workflows and a
# "Read Me First" note with the first-launch steps: the app is signed with a
# self-signed certificate, not a Developer ID, so Gatekeeper blocks it until the user
# clicks Open Anyway. The note sits next to the app because that is what people are
# looking at when the warning appears.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="dist/Screenshott.app"
if [ ! -d "$APP" ]; then
    echo "no $APP — run scripts/bundle.sh first" >&2
    exit 1
fi
/usr/bin/codesign --verify --strict "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="dist/Screenshott-$VERSION.dmg"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/screenshott-dmg.XXXXXX")"
trap 'find "$STAGE" -delete' EXIT
# mktemp makes it 700, and the folder becomes the volume's root.
chmod 755 "$STAGE"

/usr/bin/ditto "$APP" "$STAGE/Screenshott.app"
ln -s /Applications "$STAGE/Applications"
scripts/pack-workflows.sh "$STAGE/Example Workflows" >/dev/null

cat > "$STAGE/Read Me First.txt" <<EOF
Screenshott $VERSION

1. Drag Screenshott onto the Applications folder.

2. Open Screenshott from Applications. macOS says it can't verify the app,
   because this preview is not signed with an Apple Developer ID. Click Done.

3. Open System Settings > Privacy & Security, scroll down, and click
   Open Anyway next to the Screenshott message. Confirm with your password
   or Touch ID. You only do this once.

4. Allow Screen Recording when asked, then choose Quit & Reopen.
   Scrolling capture can scroll for you if you also allow Accessibility
   (menu bar icon > Allow Auto-scroll).

Hotkeys: Cmd-Shift-2 area, Cmd-Shift-1 full screen, Opt-Cmd-Shift-2 scrolling,
Opt-Cmd-Shift-1 full screen into the editor. Change them in Settings.
Shottr uses Cmd-Shift-1 and Cmd-Shift-2 too; quit it or rebind one of them.

Example Workflows: double-click one to install it. Screenshott shows every
step it runs before installing.

https://github.com/adong/screenshott
EOF

if [ -e "$DMG" ]; then find "$DMG" -delete; fi
/usr/bin/hdiutil create -quiet -volname "Screenshott $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
/usr/bin/hdiutil verify -quiet "$DMG"

# Sign the image with the app's identity, so a tampered download fails verification.
identity="${SCREENSHOTT_SIGN_IDENTITY:-$(/usr/bin/codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)}"
if [ -n "$identity" ] && [ "$identity" != "(unavailable)" ]; then
    /usr/bin/codesign --force --sign "$identity" "$DMG" && echo "signed dmg with: $identity"
else
    echo "WARNING: couldn't tell which identity signed the app; the dmg is unsigned." >&2
fi

/usr/bin/shasum -a 256 "$DMG"
echo "dmg: $PWD/$DMG"
