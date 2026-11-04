import AppKit
import Carbon.HIToolbox
import ScreenshottCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    /// A bench run gets throwaway settings: temp save folder, no sound, no thumbnails.
    private let preferences = Preferences(defaults: Bench.defaults ?? .standard)
    private lazy var shortcuts = ShortcutCenter(preferences: preferences)
    // Not private, like `overlay` below: SelfTest.swift drives them, and Bench.swift
    // points `delivery` at a private pasteboard.
    lazy var delivery = Delivery(preferences: preferences)
    lazy var presets = PresetRunner(app: self, delivery: delivery)
    lazy var workflows = WorkflowStore()
    lazy var workflowRunner = WorkflowRunner(store: workflows, delivery: delivery)
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
        delivery.openEditor = { [weak self] item in self?.openInEditor(item) }
        delivery.runWorkflow = { [weak self] id, item, log in _ = self?.workflowRunner.run(id, on: item, log: log) }
        delivery.thumbnails.workflows = { [weak self] in
            self?.workflows.installed.map { ($0.name, .workflow($0.id)) } ?? []
        }
        presets.settings.installedWorkflows = { [weak self] in self?.workflows.ids ?? [] }
        if ReadmeShots.directory != nil { workflows.examplesOnly = true }
        Permissions.requestScreenCaptureIfNeeded()
        if Permissions.hasScreenCapture { ShareableContentCache.start() }
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
        if let runs = Bench.runs {
            Task { await runBench(runs: runs) }
        }
        if let probe = DisclaimCheck.probe {
            Task { await DisclaimCheck.run(probe: probe) }
        }
        if SelfTest.requested {
            Task { await runSelfTest() }
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
        menu.setSubmenu(workflowsMenu(), for: menu.addItem(withTitle: "Workflows", action: nil, keyEquivalent: ""))
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

    /// Each workflow runs on the last capture; then install and the folder.
    private func workflowsMenu() -> NSMenu {
        let menu = NSMenu()
        let hasCapture = delivery.last != nil
        if workflows.installed.isEmpty {
            menu.addItem(withTitle: "No Workflows Installed", action: nil, keyEquivalent: "").isEnabled = false
        } else {
            menu.addItem(withTitle: hasCapture ? "Run on Last Capture" : "Run on Last Capture (none yet)",
                         action: nil, keyEquivalent: "").isEnabled = false
            for workflow in workflows.installed {
                let item = menu.addItem(withTitle: workflow.name, action: #selector(runWorkflowFromMenu(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = workflow.id
                item.isEnabled = hasCapture
                item.indentationLevel = 1
                if let icon = workflow.icon {
                    icon.size = NSSize(width: 16, height: 16)
                    item.image = icon
                }
            }
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Install Workflow…", action: #selector(installWorkflow), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Open Workflows Folder", action: #selector(openWorkflowsFolder), keyEquivalent: "")
            .target = self
        // Items with no action are enabled by hand above; keep AppKit from overriding that.
        menu.autoenablesItems = false
        return menu
    }

    @objc private func runWorkflowFromMenu(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String, let last = delivery.last else { return }
        delivery.run(.workflow(id), on: last, log: "menu")
    }

    @objc private func installWorkflow() { workflows.chooseAndInstall() }

    @objc private func openWorkflowsFolder() { workflows.openFolder() }

    /// Double-clicking a `.screenshottworkflow` lands here (Info.plist declares the type).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.pathExtension == WorkflowManifest.fileExtension {
            workflows.install(from: url)
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
            settings = SettingsWindowController(
                preferences: preferences, shortcuts: shortcuts, presets: presets.settings, workflows: workflows
            )
        }
        settings?.show()
    }

    var settingsWindow: NSWindow? { settings?.window }
    var settingsModel: SettingsModel? { settings?.model }

    @objc private func openLog() { NSWorkspace.shared.open(Log.url) }

    // MARK: - Capture

    /// Display under the mouse → the preset's action (copy + archive + thumbnail).
    /// Bench.swift times it.
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
                capture: capture, windows: windows, enterAction: enterAction,
                barItems: OverlayActionBar.items(workflows: workflows.installed)
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
        if result?.action != .editor { _ = previousApp?.activate(options: []) }
        previousApp = nil
    }
}
