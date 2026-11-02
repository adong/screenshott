import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// LSUIElement already hides the Dock icon inside the .app; this covers `swift run` too.
app.setActivationPolicy(.accessory)
app.run()
