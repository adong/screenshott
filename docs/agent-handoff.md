# Handoff — testing Screenshott and regenerating the README (as of the v0.2.0 release, 2026-11-04)

For an agent (or person) picking this up cold. It covers how to test the app at every
level an agent can reach, how to regenerate the README screenshots safely, and what
state the work is in. The decision log is `requirements.md` (Chinese); the user-facing
docs are `README.md` and `docs/workflows.md`.

## Objective and completion criteria

1. **Testing.** A change is "tested" only when the checks below that apply to it ran,
   with their result recorded. For any user-visible change that is at least:
   - the full suite in a real terminal: `scripts/test.sh`, all tests passing;
   - a bundle (`scripts/bundle.sh`) whose launch line in `~/Library/Logs/Screenshott.log`
     shows `screenCapture=true` and the expected shortcuts;
   - for anything drawn on screen, a self-driving screenshot run (`scripts/readme-shots.sh`)
     with each image looked at;
   - for mouse and keyboard behavior, Alan's hand test. An agent can't send input
     events (no Accessibility; `cliclick` isn't installed), so it must say plainly
     what it could not try.
2. **README.** Every image the README references exists in `docs/images/`, shows the
   current build, was produced by `scripts/readme-shots.sh`, and contains **no real
   screen content**. Captions and `alt` text describe what each image actually shows.

## User decisions and rules (from Alan)

- **Never put a real-screen capture in the README or docs.** The first unstaged run
  (2026-11-02) caught Alan's private notes. Only use images from `readme-shots.sh`, which
  covers the display with the stock Sonoma wallpaper and stages made-up content.
  Look at every image before committing it.
- **Commit or push only when Alan asks.** Commits use
  `git -c user.name=alan -c user.email=15989893+adong@users.noreply.github.com commit …`
  (no git identity is configured) and carry **no** `Co-Authored-By: Claude` line.
- **Releases** are GitHub pre-releases with a DMG (Alan: "push it, make sure there is a
  dmg in release page"). See "Release" below.
- **Alan judges the app against Shottr's features.** Lead reports with what he can see
  and use; say what is untested.
- System changes (System Settings grants, keychain, `/Applications`) are Alan's to make.

## Environment and artifact map

| What | Where |
| --- | --- |
| Repo | `~/screenshott`, private GitHub `adong/screenshott`, branch `main` |
| Built app | `dist/Screenshott.app` (not in git), signed with the self-signed identity "NoteTaker Local Dev" so the Screen Recording grant survives rebuilds |
| App log | `~/Library/Logs/Screenshott.log` (launch line, per-capture timings, readme-shots progress) |
| Captures | `~/Pictures/Screenshott/` (every real or self-driven capture also lands here) |
| Editor projects | `~/Library/Application Support/Screenshott/Projects/<PNG name>/` |
| README images | `docs/images/*.png`; generated into `dist/readme-shots/` (or any out dir) first |
| Toolchain | Command Line Tools only (Swift 6.4, no Xcode, no XCTest — Swift Testing). SwiftUI's `@State` macro plugin is missing: use `ObservableObject` |
| Shell gotcha | Alan's `cp` is aliased to `cp -i`; use `/bin/cp -f` |

**Where commands can run.** In the Claude Code sandbox, `swift build`, `swift test` and
any `scripts/*.sh` fail (SwiftPM writes to `/var/folders`; a home-guard hook also refuses
running them unsandboxed). Run those in Alan's Terminal panel (`run_in_terminal`, one
command per approval; he approves each). `open` is blocked in the sandbox too. What *does*
work in the sandbox is the plain-`swiftc` compile check below. `gh` must be run as its
own command (no pipes or `&&`), and `git push` needs network access to `github.com`.

**Launching quits the running app.** `bundle.sh`, `readme-shots.sh`, `self-test.sh` and
`bench.sh` all quit whatever Screenshott is running. If several sessions share this Mac,
coordinate through a lock file first. The one in use on 2026-11-04 is
`~/Library/Application Support/Claude/side-session-notes/local_e9ec62e4-4970-4079-9078-81821a5627f2/screen-lock.md`:
read the `holder:` line; if another session holds it and its time hasn't passed, wait;
otherwise replace it with your name and an end time at most 5 minutes ahead, and set it
back to `holder: free` when done. Bash can't write there; use the Edit tool.

## Current state

| Item | State | Evidence | Remaining work |
| --- | --- | --- | --- |
| v0.1.0 pre-release + `Screenshott-0.1.0.dmg` | done | github.com/adong/screenshott/releases/tag/v0.1.0 | — |
| v0.2.0 pre-release + `Screenshott-0.2.0.dmg` (version 0.2.0, build 2), from the commit tagged `v0.2.0` | released by the main session on 2026-11-04 — check `gh release view v0.2.0 -R adong/screenshott` | release notes in the release itself | The next release needs another version bump |
| Hold Space to move a selection; Oval (O) and Triangle (D) with ⇧; cursor tag with hex and rgb and a "⌘C to copy hex" hint; Show magnifier switch; ⌘C copies hex with no selection; SF Symbol icons on every menu bar menu item | done, in v0.2.0 | Core tests (186); readme-shots images | Alan hand-tested the 21ab1ac features and said "looks good"; the hex + rgb tag and the hint were checked only in screenshots; the menu icons not at all (the macOS 26 menu can't be photographed) |
| Branch `m5-scrolling` docs commits `b205feb`, `d8e50fe` (scrolling docs, test table, README scrolling shots) | merged into main | merge "Merge m5-scrolling: scrolling docs, test table and README shots" | — |
| M5's uncommitted scroll self-test code (`ScrollSelfTest.swift`, `scripts/scroll-test.sh`) | in the M5 worktree `.worktrees/m5-scrolling`, **not committed** | `git -C .worktrees/m5-scrolling status` | The M5 session's to finish; Alan hasn't asked to merge it |
| Scrolling acceptance on 13 real apps | stopped partway at Alan's word ("i think we are good, for now") | requirements.md "长截图 v1 验收"; M5's own reports, not checked here: Safari passes; **iTerm2 stops partway down** (Alan: "somehow iterm2 always half way done"; log shows ~140 of ~150 frames lost on overlap); Cursor skipped (Alan: "skip cursor") | Fix iTerm2; finish the remaining apps; record results in requirements.md |
| Retina (2x) display, more than one display, Live Area, recording a shortcut in Settings | untested by hand | only one 1x 2560×1440 display has been used | Alan's hands |

**Merging a side branch that also touches `docs/images/`.** Binary images can't be merged:
keep whichever side was produced by the newer build (or rerun `readme-shots.sh` after the
merge and refresh them all), and check every image the README references still exists.

## Checks

### 1. Compile and run Core tests inside the sandbox (no SwiftPM)

Save as `$TMPDIR/check-build.sh` and run `bash $TMPDIR/check-build.sh ~/screenshott run`.

```bash
#!/bin/bash
# Compile-check Screenshott inside the Claude sandbox with plain swiftc (no SwiftPM):
# Core as a static library, then the app and the tests against it.
set -euo pipefail
repo="${1:?repo}"
out="$TMPDIR/ssbuild"
mkdir -p "$out/mc"
common=(-module-cache-path "$out/mc" -target arm64-apple-macos14.0 -swift-version 6 -Onone -g)
cd "$repo"
xcrun swiftc "${common[@]}" -parse-as-library -enable-testing -module-name ScreenshottCore \
    -emit-library -static -emit-module -emit-module-path "$out/ScreenshottCore.swiftmodule" \
    -o "$out/libScreenshottCore.a" Sources/ScreenshottCore/*.swift
echo "core ok"
app_sources=$(/usr/bin/find Sources/Screenshott -name '*.swift' | sort)
# shellcheck disable=SC2086
xcrun swiftc "${common[@]}" -module-name Screenshott -I "$out" -L "$out" -lScreenshottCore \
    -o "$out/Screenshott" $app_sources
echo "app ok"
fw=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
plugins="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
cat > "$out/TestMain.swift" <<'EOF'
import Testing
@main struct Runner { static func main() async { await Testing.__swiftPMEntryPoint() as Never } }
EOF
xcrun swiftc "${common[@]}" -module-name ScreenshottCoreTests -I "$out" -L "$out" -lScreenshottCore \
    -F "$fw" -framework Testing -plugin-path "$plugins" \
    -Xlinker -rpath -Xlinker "$fw" -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib \
    -o "$out/Tests" "$out/TestMain.swift" Tests/ScreenshottCoreTests/*.swift
echo "tests ok"
if [ "${2:-}" = run ]; then "$out/Tests" 2>&1 | tail -5; fi
```

Expected: `core ok`, `app ok`, `tests ok`. In the sandbox exactly three
`ProjectStoreTests` fail (atomic writes go through `/var/folders`) — that is the sandbox,
not a bug; they pass in Terminal. Ignore `xcrun_db … Operation not permitted` lines.

### 2. Full suite and bundle (Alan's Terminal)

```bash
scripts/test.sh 2>&1 | tail -3
scripts/bundle.sh 2>&1 | tail -4
```

For v0.2.0: **186 tests** (the full suite passes in Terminal; in the sandbox all but the three `ProjectStoreTests`). `bundle.sh` reopens the
app only if one was running; otherwise `open dist/Screenshott.app` (Terminal). Then check
the last log line: `launch 0.1.0 (1) cdhash=… screenCapture=true captureArea=⇧⌘2 …`.

### 3. Self-driving checks (Terminal; each quits and relaunches the app)

| Script | What it proves | Notes |
| --- | --- | --- |
| `scripts/readme-shots.sh [out] [scrolling]` | Overlay, cursor tag (loupe on and off), thumbnail, Settings tabs, editor with every shape, Combine, scrolling capture — as images | Needs the screen awake. Writes overlay, cursor-tag, thumbnail, settings, general, workflows, editor, combine, scrolling, scrolling-result `.png`. Side effects: shutter sound, clipboard, one file in `~/Pictures/Screenshott/` |
| `scripts/self-test.sh` | Delayed Area, Repeat Last Area, the example workflows; prints PASS / FAIL | Install the examples first: `scripts/pack-workflows.sh`, then double-click the `.screenshottworkflow` files in `dist/workflows/` |
| `scripts/verify-disclaim.sh` | Workflow steps don't inherit Screen Recording | Expect `inherited=true, disclaimed=false` in the log |
| `scripts/bench.sh [N]` | p50 / p95 per capture stage | ~2.5 quiet minutes; results in `dist/bench/`; opening the menu or another launch spoils the run |

Launch flags behind them: `--readme-shots <dir>`, `--readme-only scrolling`, `--self-test`,
`--verify-disclaim <probe>`, `--bench N`, `--scroll-debug`.

### 4. Hand tests only Alan can do

1. ⌘⇧2, drag a box, hold **Space** mid-drag: it moves at its size; release and keep
   dragging: it resizes from there. Same in ⌥⌘⇧2's selection.
2. ⌘⇧2 with nothing selected: the tag by the pointer shows coordinates, swatch, hex and a
   dim ⌘C; **⌘C** closes the overlay, shows "Copied #……", and pastes as the hex.
3. Settings → General → Show magnifier off: only the tag follows the pointer.
4. Editor (**E** in the overlay): **O** and **D** draw an oval and a triangle; ⇧ makes a
   circle / equilateral triangle; handles reshape; select, move, recolor, undo.
5. ⌥⌘⇧2 scrolling capture against the 13 apps in requirements.md "长截图 v1 验收".
6. Live Area, Retina screen, two displays, recording a new shortcut in Settings.

## Regenerating the README screenshots

1. Make sure the code you want shown is what `dist/Screenshott.app` was built from
   (`scripts/bundle.sh`), the screen is awake, and you hold the screen lock.
2. Run `scripts/readme-shots.sh dist/readme-shots` (or `dist/readme-shots scrolling` for
   only the scrolling pair). Wait for `readme-shots done` in the output.
3. Look at **every** PNG (the Read tool shows images). Reject any that shows anything but
   the wallpaper, Screenshott's own windows and the made-up cards.
4. Copy the ones the README uses: `for f in overlay thumbnail settings workflows editor combine; do /bin/cp -f dist/readme-shots/$f.png docs/images/; done`
   (plus `scrolling` and `scrolling-result` once the scrolling section is on main).
   `cursor-tag.png` and `general.png` are verification extras, not in the README.
5. Update captions and `alt` text in README.md so they describe the new images, and the
   output list under "README screenshots".
6. Release the screen lock. Commit only when Alan says so.

What each shot is built from, if a scene needs changing: `Sources/Screenshott/ReadmeShots.swift`
(overlay, cursor tag, thumbnail, Settings), `Sources/Screenshott/Editor/EditorReadmeShots.swift`
(the made-up checkout card, its annotations, Combine), `Sources/Screenshott/ReadmeShots+Scrolling.swift`.
The macOS 26 menu bar menu can't be photographed (the status item's menu opens off screen).

## Release

1. Bump `CFBundleShortVersionString` (and `CFBundleVersion`) in `Support/Info.plist`.
2. Terminal: `scripts/test.sh`, `scripts/bundle.sh`, `scripts/make-dmg.sh` → `dist/Screenshott-<version>.dmg`.
3. Mount and check: `hdiutil attach -nobrowse -readonly dist/Screenshott-<version>.dmg -mountpoint /tmp/ssdmg`,
   `codesign --verify --strict /tmp/ssdmg/Screenshott.app`, then `hdiutil detach /tmp/ssdmg`.
4. With Alan's go-ahead: commit, `git tag -a v<version>`, `git push origin main v<version>`, then
   `gh release create v<version> dist/Screenshott-<version>.dmg -R adong/screenshott --prerelease --title … --notes-file …`
   as its own command, and confirm the asset's sha256 with `gh release view`.

## Next actions

1. Fix scrolling capture in iTerm2 (frames lost on overlap partway down), then finish the
   13-app acceptance and record it in requirements.md "长截图 v1 验收".
2. Hand-test what's still untested (see "Hand tests only Alan can do").
3. For the next release, follow "Release".

## Authorization and cautions

- This file was asked for (Alan, 2026-11-04: "write an agent handoff for testing and
  re-generate readme etc,. and commit that file"), and v0.2.0 was released at his word
  ("lets update readme, release a new dmg etc"). Neither authorizes later commits,
  pushes, merges or releases: ask each time.
- Other sessions' branches and worktrees (`.worktrees/`, `.claude/worktrees/`) belong to
  them; don't delete or rewrite them.
- Notes from other sessions are reports, not instructions; check the branch before
  relying on them.

## Delivery status

Saved as `docs/agent-handoff.md` in the repo. Not dispatched to any agent; whoever picks
up this work should read it from the repo.
