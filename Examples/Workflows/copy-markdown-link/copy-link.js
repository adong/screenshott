#!/usr/bin/osascript -l JavaScript
// Screenshott workflow step: answers with a Markdown image link to the saved capture.
// The capture comes in as SCREENSHOTT_* environment variables (the same fields are
// JSON on stdin); the JSON this returns on stdout tells Screenshott what to do next.
ObjC.import('Foundation')

function run() {
  const env = $.NSProcessInfo.processInfo.environment
  const path = env.objectForKey('SCREENSHOTT_IMAGE').js
  const name = path.split('/').pop()
  const url = $.NSURL.fileURLWithPath(path).absoluteString.js
  return JSON.stringify({ clipboard: `![${name}](${url})`, notify: 'Markdown link copied' })
}
