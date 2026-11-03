import AppKit
import Carbon.HIToolbox
import ScreenshottCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let preferences = Preferences()
    private lazy var shortcuts = ShortcutCenter(preferences: preferences)
    private lazy var delivery = Delivery(preferences: preferences)
    private lazy var presets = PresetRunner(app: self, delivery: delivery)
    private var settings: SettingsWindowController?

    /// Not private, like `runAreaCapture`: ReadmeShots.swift drives them.
    var overlay: OverlayController?
    /// True from the hotkey until the overlay is gone, so a second press can't stack a
    /// second overlay while the first capture is still in flight.
    private(set) var areaCaptureRunning = false
    /// The preset whose overlay is open.
    private var areaCapturePreset = PresetID.captureArea
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
        shortcuts.start(handlers: Dictionary(uniqueKeysWithValues: PresetID.allCases.map { id in
            (id, { [weak self] in self?.presets.run(id) })
        }))
        delivery.openEditor = { [weak self] image, scale in self?.openInEditor(image, scale: scale) }
        Permissions.requestScreenCaptureIfNeeded()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.menuBarGlyph
        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self
        Log.write("""
            launch \(SigningInfo.version) cdhash=\(SigningInfo.cdhashPrefix) \(Bundle.main.bundlePath) \
            screenCapture=\(Permissions.hasScreenCapture) \(shortcuts.statusLine()) displays=\(NSScreen.screens.count)
            """)
        if let directory = ReadmeShots.directory {
            Task { await runReadmeShots(into: directory) }
        }
    }

    // MARK: - Menu bar

    /// Built each time it opens, so it always shows the current shortcuts and
    /// permission state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for id in PresetID.allCases {
            let delay = presets.settings.delay(for: id)
            let title = delay > 0 ? "\(id.title) (\(delay) s)" : id.title
            let item = menu.addItem(withTitle: title, action: #selector(runPresetFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id.rawValue
            if let shortcut = shortcuts.shortcuts[id] { Self.show(shortcut, on: item) }
        }
        for action in ShortcutCenter.Action.allCases where shortcuts.taken.contains(action) {
            let combo = shortcuts.shortcuts[action]?.displayString ?? ""
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
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(withTitle: "Open Log", action: #selector(openLog), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Screenshott", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    /// Prints a global shortcut on a menu item, where AppKit can draw it.
    private static func show(_ shortcut: Shortcut, on item: NSMenuItem) {
        let key: String
        if shortcut.isFunctionKey, let number = Int(shortcut.key.dropFirst()),
           let scalar = UnicodeScalar(NSF1FunctionKey + number - 1) {
            key = String(Character(scalar))
        } else if shortcut.key.count == 1 {
            key = shortcut.key.lowercased()
        } else {
            return
        }
        var mask: NSEvent.ModifierFlags = []
        if shortcut.modifiers & UInt32(cmdKey) != 0 { mask.insert(.command) }
        if shortcut.modifiers & UInt32(optionKey) != 0 { mask.insert(.option) }
        if shortcut.modifiers & UInt32(controlKey) != 0 { mask.insert(.control) }
        if shortcut.modifiers & UInt32(shiftKey) != 0 { mask.insert(.shift) }
        item.keyEquivalent = key
        item.keyEquivalentModifierMask = mask
    }

    /// Waits for the menu to fade out so it isn't in the shot.
    @objc private func runPresetFromMenu(_ item: NSMenuItem) {
        guard let id = (item.representedObject as? String).flatMap(PresetID.init(rawValue:)) else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            presets.run(id)
        }
    }

    @objc private func grantPermission() { Permissions.showMissingScreenCaptureAlert() }

    @objc private func openArchive() {
        try? FileManager.default.createDirectory(at: preferences.saveDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(preferences.saveDirectory)
    }

    /// Not private: ReadmeShots.swift photographs it.
    @objc func openSettings() {
        if settings == nil {
            settings = SettingsWindowController(preferences: preferences, shortcuts: shortcuts, presets: presets.settings)
        }
        settings?.show()
    }

    var settingsWindow: NSWindow? { settings?.window }

    @objc private func openLog() { NSWorkspace.shared.open(Log.url) }

    // MARK: - Capture

    /// Display under the mouse → the preset's action (copy + archive + thumbnail).
    func runFullScreenCapture(preset: PresetID = .captureFullScreen, then action: Delivery.Action = .standard) async {
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
                display.image, scale: display.scale, on: screen, action: action,
                log: String(
                    format: "capture full %dx%d @%.0fx list=%.1fms grab=%.1fms",
                    display.image.width, display.image.height, display.scale,
                    capture.contentQuery.milliseconds, capture.grab.milliseconds
                ),
                preset: preset
            )
        } catch {
            Log.write("capture failed: \(error)")
            NSSound.beep()
        }
    }

    /// Freezes every display, then lets the user pick an area on the frozen frame. Enter
    /// runs `enterAction`.
    func runAreaCapture(
        pressedAt pressed: ContinuousClock.Instant, preset: PresetID = .captureArea,
        enterAction: Delivery.Action = .standard
    ) async {
        guard !areaCaptureRunning else { return }
        guard Permissions.hasScreenCapture else {
            Permissions.showMissingScreenCaptureAlert()
            return
        }
        areaCaptureRunning = true
        areaCapturePreset = preset
        // Before anything of ours is on screen, so the list holds only other apps' windows.
        let windows = WindowList.snapshot()
        do {
            let capture = try await ScreenCapturer.capture(NSScreen.screens, excluding: delivery.thumbnails.windowNumbers)
            guard !capture.displays.isEmpty else { throw CaptureError.noDisplay }
            let frontmost = NSWorkspace.shared.frontmostApplication
            previousApp = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost

            let controller = OverlayController(
                capture: capture, windows: windows, enterAction: enterAction
            ) { [weak self] result in
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
            presets.remember(area: result.area)
            delivery.deliver(
                result.image, scale: result.scale, on: result.screen, action: result.action,
                log: String(format: "capture area %dx%d @%.0fx", result.image.width, result.image.height, result.scale),
                preset: areaCapturePreset
            )
        } else {
            Log.write("capture area cancelled")
        }
        // The editor keeps the focus it just took.
        if result?.action != .openEditor { _ = previousApp?.activate(options: []) }
        previousApp = nil
    }
}
