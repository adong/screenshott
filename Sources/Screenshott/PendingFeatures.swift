import AppKit
import ScreenshottCore

/// Entry points other milestones fill in. Until they merge, each one logs, says so and
/// beeps, so its preset already has a hotkey, a menu item and a place in Settings.
/// Merging M3 or M5 deletes the matching stub here.
extension AppDelegate {
    /// M3: opens the editor on a saved capture (`item.file`).
    func openInEditor(_ item: CaptureItem) {
        Log.write("editor: arrives with M3 (\(item.file?.lastPathComponent ?? "unsaved"), @\(Int(item.scale))x)")
        Toast.show("The editor arrives with M3")
        NSSound.beep()
    }

    /// M5: starts a scrolling capture.
    func runScrollingCapture() {
        Log.write("scrolling capture: arrives with M5")
        Toast.show("Scrolling capture arrives with M5")
        NSSound.beep()
    }
}
