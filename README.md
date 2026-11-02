<p align="center">
  <img src="docs/images/icon.png" width="160" alt="Screenshott app icon">
</p>

<h1 align="center">Screenshott</h1>

<p align="center">
  A small, fast, keyboard-first screenshot app for macOS.<br>
  Native Swift, built with nothing but the Command Line Tools.
</p>

---

Screenshott is a menu bar app in the spirit of [Shottr](https://shottr.cc): press a
hotkey, get a pixel-exact PNG on the clipboard and in an archive folder, then
optionally mark it up. It is being built milestone by milestone; each milestone is a
vertical slice you can use day to day.

> **Status: M0 (skeleton) works.** Full-screen capture is usable today. Area capture,
> the editor, Combine and scrolling capture are next — see [Roadmap](#roadmap).

## What works today

| | |
|---|---|
| **Menu bar app** | Lives in the menu bar, no Dock icon. The menu bar glyph is a template image, so it follows light and dark menu bars. |
| **⌘⇧1 full screen** | Captures the display under the mouse. Global hotkey with no Accessibility permission needed. |
| **Clipboard + archive** | Every capture goes to the clipboard *and* to `~/Pictures/Screenshott/`, so the next copy never loses a shot. Files are named `Screenshott 2026-11-02 at 09.41.27.png`. |
| **Retina-correct PNGs** | Saved at physical pixels with 144 DPI metadata, so a 2x capture opens at its real size instead of double. |
| **Fast** | About 115 ms from hotkey to clipboard on a 2560×1440 display (M3 Max). Each stage is timed in the log. |
| **Permission that sticks** | Signed with a stable self-signed certificate, so the Screen Recording grant survives rebuilds. If the grant is missing, the app offers *Open System Settings* and *Quit & Reopen*. |

## Roadmap

| Milestone | What it adds | Status |
|---|---|---|
| **M0 Skeleton** | Menu bar app, ⌘⇧1 full screen → clipboard + archive, signing, permission flow | ✅ Done |
| **M1 Frozen overlay** | ⌘⇧2 area capture on a frozen screen: drag to select, click to snap to a window, magnifier, 1 px arrow-key nudge, multi-display, floating thumbnail with drag-out | 🚧 In progress |
| **M2 Presets & hotkeys** | Every hotkey is a preset: frozen or live × no selection / area / window × what Enter does. Hotkey recorder, settings, shared action interface | Planned |
| **M3 Editor** | Crop, zoom, arrow, rectangle, text, pixelate (with a solid-cover mode that really replaces the pixels). Re-editable after saving | Planned |
| **M4 Combine** | Put several captures on one canvas with automatic layout | Planned |
| **M5 Scrolling capture** | Auto-scroll or manual scroll, overlap stitching, sticky header/footer removal, live stitch preview, 30,000 px cap | Planned |
| **M7 Workflows** | Alfred-style post-capture workflows: scripts, Apple Shortcuts or URL templates that receive the image and decide where it goes next | Planned |
| **M6 Polish** | Benchmark mode (p50/p95 against Shottr's 17 ms grab), launch at login | Planned |

### Planned default hotkeys

| Preset | Screen | How you pick | After Enter | Hotkey |
|---|---|---|---|---|
| Area | Frozen | Drag; click snaps to a window | Copy + save + thumbnail | ⌘⇧2 |
| Full screen | Frozen | Display under the mouse | Copy + save + thumbnail | ⌘⇧1 |
| Full screen → editor | Frozen | Crop in the editor | Open the editor | ⌥⌘⇧1 |
| Scrolling | Live | Drag, then scroll | Stitch → thumbnail | ⌥⌘⇧2 |
| Live area, repeat last area, delayed | — | — | — | Unbound |

Inside the overlay: **Enter** runs the preset's action · **⌘C** copy only ·
**⌘S** save as · **E** open in the editor · **Esc** cancel.

These avoid the system's ⌘⇧3 / ⌘⇧4 / ⌘⇧5. Shottr uses ⌘⇧1 and ⌘⇧2 by default,
so quit it (or rebind it) while running Screenshott.

## Build

Requirements: macOS 14 or later and the Xcode **Command Line Tools** (Swift 6).
Xcode itself is not needed.

```bash
scripts/bundle.sh          # release build → dist/Screenshott.app
scripts/bundle.sh debug    # debug build
open dist/Screenshott.app
```

`bundle.sh` quits a running Screenshott before replacing the bundle and reopens it
afterwards, so you never test the old build by accident.

**Signing.** macOS ties the Screen Recording permission of an ad-hoc signed app to
its exact code hash, which changes on every build, so the permission would silently
lapse after each rebuild. Create a self-signed code-signing certificate once
(Keychain Access → Certificate Assistant → Create a Certificate → Self Signed Root,
type *Code Signing*) and name it `Screenshott Dev`, or point
`SCREENSHOTT_SIGN_IDENTITY` at an existing one. The script falls back to ad-hoc
signing with a warning.

**Tests.** `scripts/test.sh` runs the Swift Testing suite. It passes the
`TestingMacros` plugin path explicitly, which some Command Line Tools installs need.

**Icon.** `scripts/make-icon.sh` redraws `Support/AppIcon.icns` from the vector
code in `Tools/MakeIcon`, rendering each size separately so small sizes stay crisp.

## Project layout

```
Sources/Screenshott/       AppKit app: menu bar, hotkeys, capture, permissions
Sources/ScreenshottCore/   Pure logic with no UI, covered by unit tests
Tests/                     Swift Testing suite for ScreenshottCore
Tools/MakeIcon/            App icon drawing code
Support/                   Info.plist and AppIcon.icns
scripts/                   bundle.sh, test.sh, make-icon.sh
requirements.md            Decision log: every product and technical choice, with reasons (Chinese)
```

The log is at `~/Library/Logs/Screenshott.log`. Each launch records the version,
code hash and permission state; each capture records how long listing displays,
grabbing pixels, encoding and saving took.
