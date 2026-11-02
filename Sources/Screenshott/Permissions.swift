import AppKit

/// Screen Recording permission. macOS reads the grant when the process starts, so
/// flipping the switch in System Settings does nothing until Screenshott relaunches.
@MainActor
enum Permissions {
    static var hasScreenCapture: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt — macOS only does that once per app. After that the
    /// user has to go to System Settings themselves.
    static func requestScreenCaptureIfNeeded() {
        if !hasScreenCapture { _ = CGRequestScreenCaptureAccess() }
    }

    static func showMissingScreenCaptureAlert() {
        let alert = NSAlert()
        alert.messageText = "Screenshott needs Screen Recording permission"
        alert.informativeText = """
            Turn on Screenshott in System Settings → Privacy & Security → \
            Screen & System Audio Recording, then reopen Screenshott. \
            macOS only picks up the permission at launch.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit & Reopen")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn: openScreenCaptureSettings()
        case .alertSecondButtonReturn: relaunch()
        default: break
        }
    }

    static func openScreenCaptureSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    /// A process can't reopen itself after exiting, so a detached shell waits for this
    /// one to quit and then opens the bundle again.
    static func relaunch() {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? shell.run()
        NSApp.terminate(nil)
    }
}
