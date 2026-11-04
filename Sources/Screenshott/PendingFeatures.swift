import AppKit
import ScreenshottCore

/// Entry points other milestones fill in. Until they merge, each one logs, says so and
/// beeps, so its preset already has a hotkey, a menu item and a place in Settings.
/// Merging M5 deletes the stub here.
extension AppDelegate {
    /// M5: starts a scrolling capture.
    func runScrollingCapture() {
        Log.write("scrolling capture: arrives with M5")
        Toast.show("Scrolling capture arrives with M5")
        NSSound.beep()
    }
}
