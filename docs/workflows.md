# Writing a Screenshott workflow

A workflow decides where a capture goes after it is taken: upload it, resize it, file
it, hand it to an Apple Shortcut, open a URL. It runs only *after* a capture, never
before or during one.

You can run a workflow from:

- the overlay's action bar, under the selection, or its number key **1–9**
- a thumbnail: the ⚡︎ button that appears on hover, or the right-click menu
- the menu bar: **Workflows ▸** runs it on the last capture
- a preset: Settings → Presets → **Then**. The preset's hotkey then captures and runs
  the workflow in one go.

The three examples in [`Examples/Workflows`](../Examples/Workflows) show every kind of
step. Run `scripts/pack-workflows.sh` to zip them, then double-click one in
`dist/workflows/` to install it.

## The bundle

A workflow is a folder zipped into a file named `*.screenshottworkflow`:

```
copy-markdown-link/
  workflow.json
  copy-link.js        any scripts the steps run
  icon.png            optional, shown in menus and the action bar
```

```bash
/usr/bin/ditto -c -k --norsrc --noextattr --noqtn copy-markdown-link copy-markdown-link.screenshottworkflow
```

`workflow.json` can be at the top of the zip or inside a single top-level folder, so
Finder's *Compress* also works if you rename the result. Double-clicking the file shows
everything the workflow will run and asks before installing it into
`~/Library/Application Support/Screenshott/Workflows/<id>/`. Installing an id that is
already there replaces it and moves the old copy to the Trash. Removing a workflow in
Settings also moves it to the Trash.

## workflow.json

```json
{
  "format": 1,
  "id": "com.example.upload",
  "name": "Upload",
  "version": "1.0",
  "author": "You",
  "description": "One line for the install confirmation and Settings.",
  "icon": "icon.png",
  "steps": [
    { "type": "script", "path": "upload.sh", "args": ["--public"], "timeout": 60 },
    { "type": "action", "action": "copy" }
  ]
}
```

| Field | | |
|---|---|---|
| `id` | required | Letters, digits, `.` `-` `_`, starting with a letter or digit. Also the install folder's name. |
| `name` | required | What menus and the action bar show. |
| `steps` | required | One or more, run in order. The first step that fails stops the rest. |
| `format` | optional | `1`. A newer format is refused with "needs a newer Screenshott". |
| `version`, `author`, `description` | optional | Shown when installing and in Settings. |
| `icon` | optional | A PNG in the bundle, ideally 64 × 64. |

Paths are relative to the bundle and must stay inside it: no `/…`, `~`, `..`, and no
symlinks that point out.

## Steps

| `type` | Fields | What it does |
|---|---|---|
| `script` | `path`, `args` (optional), `timeout` (seconds, 1–300, default 30) | Runs an executable from the bundle: any language with a `#!` line, or a binary. |
| `shortcut` | `name` | Runs the Apple Shortcut with that name from your library, with the PNG as its input. Up to 120 s. |
| `open-url` | `url` | Opens a URL built from a template; see below. |
| `action` | `action`: `copy`, `save`, `save-as`, `thumbnail` or `editor` | A built-in action on the current image. |

Before the first step runs, the capture is saved to the screenshots folder, as every
capture is, so steps always have a real file to work on.

### Scripts

A script step starts in the workflow's folder, with a small environment of its own
(`PATH` includes `/opt/homebrew/bin` and `/usr/local/bin`; `HOME`, `USER`, `TMPDIR`
and `LANG` are set). It learns about the capture two ways: as environment variables,
and as the same fields in JSON on stdin.

| Variable | JSON key | |
|---|---|---|
| `SCREENSHOTT_IMAGE` | `image` | Absolute path of the PNG. After a step handed back an `image`, that one. |
| `SCREENSHOTT_WIDTH`, `SCREENSHOTT_HEIGHT` | `width`, `height` | In pixels. |
| `SCREENSHOTT_SCALE` | `scale` | `2` for a full-resolution capture from a Retina screen. |
| `SCREENSHOTT_PRESET` | `preset` | The preset that took it, e.g. `captureArea`. Absent when run from a thumbnail or the menu bar. |
| `SCREENSHOTT_CAPTURED_AT` | `capturedAt` | ISO 8601. |
| `SCREENSHOTT_WORKFLOW`, `SCREENSHOTT_STEP` | `workflow`, `step` | The workflow's id and the step number, from 1. |
| `SCREENSHOTT_OUTPUT_DIR` | `outputDirectory` | An empty folder for this step to write files into. |
| `SCREENSHOTT_VERSION` | | The app version. |

stdout is for the answer: nothing, or **one JSON object** saying what to do next. Logs
go to stderr. Every key is optional:

```json
{ "clipboard": "https://example.com/abc.png", "notify": "Uploaded", "open": "https://example.com/abc", "image": "small.png" }
```

| Key | |
|---|---|
| `clipboard` | Text to put on the clipboard. |
| `notify` | A short message shown low on the screen for a few seconds. |
| `open` | A URL, or a file path, to open. |
| `image` | A replacement image for the steps after this one: an absolute path, or a path relative to `SCREENSHOTT_OUTPUT_DIR`. Its DPI sets its scale (144 = 2x). |

Unknown keys are ignored and logged, so a typo shows up in
`~/Library/Logs/Screenshott.log`. Anything on stdout that isn't a JSON object, a
non-zero exit status, or running past the timeout stops the workflow and shows which
step failed and why (with the last line of stderr). On a timeout the step's whole
process group gets SIGTERM, then SIGKILL two seconds later.

A complete script in shell, from the *Copy at 1x* example:

```sh
#!/bin/sh
set -eu
width=$(( SCREENSHOTT_WIDTH / SCREENSHOTT_SCALE ))
/usr/bin/sips --resampleWidth "$width" -s dpiWidth 72 -s dpiHeight 72 \
    "$SCREENSHOTT_IMAGE" --out "$SCREENSHOTT_OUTPUT_DIR/1x.png" >&2
printf '{"image": "1x.png"}\n'
```

### Shortcuts

A `shortcut` step runs `shortcuts run "<name>" --input-path <png>`, so build the
shortcut to receive an image (*Receive Images from Quick Actions* or *Shortcut Input*).
What it outputs from its last action matters: an image replaces the capture for the
next steps, a JSON object is read like a script's stdout, and anything else is ignored.

### URL templates

`open-url` replaces placeholders in the URL with the capture's details:

`{path}` `{filename}` `{width}` `{height}` `{scale}` `{preset}`

Each value is percent-encoded so it can't break out of its place in the URL; only `/`
is left as it is, so `file://{path}` works. Install checks that the template uses only
these names and makes a URL with a scheme.

## Permissions

Steps run out of process: a crash or hang in a script never takes the capture with it.
They run as you, so they can read and change your files; that's why installing asks
first and lists every step.

They do **not** get Screenshott's permissions. macOS normally files a child process's
privacy permissions under the app that started it, which would let any script record
the screen through Screenshott's Screen Recording grant. Screenshott starts steps with
that responsibility disclaimed (`posix_spawn` with `responsibility_spawnattrs_setdisclaim`,
as iTerm2 does), so a script that wants to record the screen has to get its own
permission. It doesn't need to: it already has the image. `scripts/verify-disclaim.sh`
checks this on a real build.
