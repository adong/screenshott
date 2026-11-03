import AppKit
import Carbon.HIToolbox
import ScreenshottCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var fullScreenHotKeyStatus: OSStatus = noErr
    private var areaHotKeyStatus: OSStatus = noErr
    private let delivery = Delivery()

    /// Not private, like `runAreaCapture`: ReadmeShots.swift drives them.
    var overlay: OverlayController?
    /// True from the hotkey until the overlay is gone, so a second press can't stack a
    /// second overlay while the first capture is still in flight.
    private var areaCaptureRunning = false
    /// The app that had focus before the overlay took it; it gets focus back after.
    private var previousApp: NSRunningApplication?

    /// The app icon reduced to a menu bar glyph: viewfinder brackets around a filled
    /// card. A template image, so macOS tints it for light and dark menu bars.
    private static let menuBarGlyph: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let frame = rect.insetBy(dx: 1.5, dy: 1.5)
            let arm: CGFloat = 4.5
            let brackets = NSBezierPath()
            for (corner, dx, dy) in [
                (NSPoint(x: frame.minX, y: frame.maxY), 1.0, -1.0),
                (NSPoint(x: frame.maxX, y: frame.maxY), -1.0, -1.0),
                (NSPoint(x: frame.minX, y: frame.minY), 1.0, 1.0),
                (NSPoint(x: frame.maxX, y: frame.minY), -1.0, 1.0),
            ] {
                brackets.move(to: NSPoint(x: corner.x, y: corner.y + dy * arm))
                brackets.line(to: corner)
                brackets.line(to: NSPoint(x: corner.x + dx * arm, y: corner.y))
            }
            brackets.lineWidth = 1.7
            brackets.lineCapStyle = .round
            brackets.lineJoinStyle = .round
            NSColor.black.setStroke()
            brackets.stroke()
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 5.5, y: 6.5, width: 7, height: 5), xRadius: 1.2, yRadius: 1.2).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        fullScreenHotKeyStatus = HotKeys.register(keyCode: kVK_ANSI_1, modifiers: cmdKey | shiftKey) {
            [weak self] in self?.captureFullScreen()
        }
        areaHotKeyStatus = HotKeys.register(keyCode: kVK_ANSI_2, modifiers: cmdKey | shiftKey) {
            [weak self] in self?.captureArea()
        }
        Permissions.requestScreenCaptureIfNeeded()
        setUpStatusItem()
        Log.write("""
            launch \(SigningInfo.version) cdhash=\(SigningInfo.cdhashPrefix) \(Bundle.main.bundlePath) \
            screenCapture=\(Permissions.hasScreenCapture) hotkey⌘⇧1=\(fullScreenHotKeyStatus) \
            hotkey⌘⇧2=\(areaHotKeyStatus) displays=\(NSScreen.screens.count)
            """)
        if let directory = ReadmeShots.directory {
            Task { await runReadmeShots(into: directory) }
        }
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.menuBarGlyph

        let menu = NSMenu()
        let area = menu.addItem(withTitle: "Capture Area", action: #selector(captureAreaFromMenu), keyEquivalent: "2")
        area.keyEquivalentModifierMask = [.command, .shift]
        area.target = self
        let full = menu.addItem(withTitle: "Capture Full Screen", action: #selector(captureFullScreenFromMenu), keyEquivalent: "1")
        full.keyEquivalentModifierMask = [.command, .shift]
        full.target = self

        for (status, combo) in [(areaHotKeyStatus, "⌘⇧2"), (fullScreenHotKeyStatus, "⌘⇧1")] where status != noErr {
            menu.addItem(withTitle: "\(combo) is taken by another app (Shottr?)", action: nil, keyEquivalent: "")
                .isEnabled = false
        }
        if !Permissions.hasScreenCapture {
            menu.addItem(withTitle: "Grant Screen Recording…", action: #selector(grantPermission), keyEquivalent: "")
                .target = self
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Screenshots Folder", action: #selector(openArchive), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Open Log", action: #selector(openLog), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Screenshott", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem.menu = menu
    }

    // Menu items wait for the menu to fade out so it isn't in the shot.

    @objc private func captureAreaFromMenu() {
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            await runAreaCapture(pressedAt: ContinuousClock.now)
        }
    }

    @objc private func captureFullScreenFromMenu() {
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            await runFullScreenCapture()
        }
    }

    @objc private func grantPermission() { Permissions.showMissingScreenCaptureAlert() }

    @objc private func openArchive() {
        try? FileManager.default.createDirectory(at: Delivery.archiveDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Delivery.archiveDirectory)
    }

    @objc private func openLog() { NSWorkspace.shared.open(Log.url) }

    // MARK: - Capture

    private func captureFullScreen() {
        Task { await runFullScreenCapture() }
    }

    private func captureArea() {
        let pressed = ContinuousClock.now
        Task { await runAreaCapture(pressedAt: pressed) }
    }

    /// Display under the mouse → copy + archive + thumbnail.
    private func runFullScreenCapture() async {
        guard !areaCaptureRunning else { return }
        guard Permissions.hasScreenCapture else {
            Permissions.showMissingScreenCaptureAlert()
            return
        }
        do {
            guard let screen = ScreenCapturer.screenUnderMouse else { throw CaptureError.noDisplay }
            let capture = try await ScreenCapturer.capture([screen], excluding: delivery.thumbnails.windowNumbers)
            guard let display = capture.displays.first else { throw CaptureError.noDisplay }
            delivery.deliver(
                display.image, scale: display.scale, on: screen, action: .standard,
                log: String(
                    format: "capture full %dx%d @%.0fx list=%.1fms grab=%.1fms",
                    display.image.width, display.image.height, display.scale,
                    capture.contentQuery.milliseconds, capture.grab.milliseconds
                )
            )
        } catch {
            Log.write("capture failed: \(error)")
            NSSound.beep()
        }
    }

    /// Freezes every display, then lets the user pick an area on the frozen frame.
    func runAreaCapture(pressedAt pressed: ContinuousClock.Instant) async {
        guard !areaCaptureRunning else { return }
        guard Permissions.hasScreenCapture else {
            Permissions.showMissingScreenCaptureAlert()
            return
        }
        areaCaptureRunning = true
        // Before anything of ours is on screen, so the list holds only other apps' windows.
        let windows = WindowList.snapshot()
        do {
            let capture = try await ScreenCapturer.capture(NSScreen.screens, excluding: delivery.thumbnails.windowNumbers)
            guard !capture.displays.isEmpty else { throw CaptureError.noDisplay }
            let frontmost = NSWorkspace.shared.frontmostApplication
            previousApp = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost

            let controller = OverlayController(capture: capture, windows: windows) { [weak self] result in
                self?.overlayFinished(result)
            }
            overlay = controller
            controller.show()
            // Taking focus is what lets the overlay set the crosshair cursor.
            NSApp.activate()
            Log.write(String(
                format: "overlay %d display(s) %d windows shown in %.1fms (list=%.1fms grab=%.1fms)",
                capture.displays.count, windows.count, (ContinuousClock.now - pressed).milliseconds,
                capture.contentQuery.milliseconds, capture.grab.milliseconds
            ))
        } catch {
            areaCaptureRunning = false
            Log.write("capture failed: \(error)")
            NSSound.beep()
        }
    }

    private func overlayFinished(_ result: OverlayController.Result?) {
        overlay = nil
        areaCaptureRunning = false
        if let result {
            delivery.deliver(
                result.image, scale: result.scale, on: result.screen, action: result.action,
                log: String(format: "capture area %dx%d @%.0fx", result.image.width, result.image.height, result.scale)
            )
        } else {
            Log.write("capture area cancelled")
        }
        _ = previousApp?.activate(options: [])
        previousApp = nil
    }
}
