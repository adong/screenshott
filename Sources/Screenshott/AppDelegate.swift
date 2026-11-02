import AppKit
import Carbon.HIToolbox
import ScreenshottCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var fullScreenHotKeyStatus: OSStatus = noErr

    static let archiveDirectory = FileManager.default
        .urls(for: .picturesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Screenshott")

    private static let shutterSound = NSSound(
        contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif",
        byReference: true
    )

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
        Permissions.requestScreenCaptureIfNeeded()
        setUpStatusItem()
        Log.write("""
            launch \(SigningInfo.version) cdhash=\(SigningInfo.cdhashPrefix) \(Bundle.main.bundlePath) \
            screenCapture=\(Permissions.hasScreenCapture) hotkey⌘⇧1=\(fullScreenHotKeyStatus)
            """)
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.menuBarGlyph

        let menu = NSMenu()
        let capture = menu.addItem(withTitle: "Capture Full Screen", action: #selector(captureFromMenu), keyEquivalent: "1")
        capture.keyEquivalentModifierMask = [.command, .shift]
        capture.target = self

        if fullScreenHotKeyStatus != noErr {
            let taken = menu.addItem(withTitle: "⌘⇧1 is taken by another app (Shottr?)", action: nil, keyEquivalent: "")
            taken.isEnabled = false
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

    @objc private func captureFromMenu() {
        // Give the menu time to fade out so it isn't in the shot.
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            await runFullScreenCapture()
        }
    }

    @objc private func grantPermission() { Permissions.showMissingScreenCaptureAlert() }

    @objc private func openArchive() {
        try? FileManager.default.createDirectory(at: Self.archiveDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Self.archiveDirectory)
    }

    @objc private func openLog() { NSWorkspace.shared.open(Log.url) }

    // MARK: - Capture

    private func captureFullScreen() {
        Task { await runFullScreenCapture() }
    }

    /// M0's one flow: display under the mouse → PNG → clipboard + archive folder.
    private func runFullScreenCapture() async {
        guard Permissions.hasScreenCapture else {
            Permissions.showMissingScreenCaptureAlert()
            return
        }
        let clock = ContinuousClock()
        do {
            let capture = try await ScreenCapturer.captureDisplayUnderMouse()
            Self.shutterSound?.play()

            let encodeStart = clock.now
            guard let png = PNGEncoder.data(from: capture.image, scale: capture.scale) else {
                throw CaptureError.encodeFailed
            }
            let encoded = clock.now

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(png, forType: .png)
            let url = try save(png)

            Log.write(String(
                format: "capture full %dx%d @%.0fx list=%.1fms grab=%.1fms encode=%.1fms copy+save=%.1fms %@",
                capture.image.width, capture.image.height, capture.scale,
                capture.contentQuery.milliseconds, capture.grab.milliseconds,
                (encoded - encodeStart).milliseconds, (clock.now - encoded).milliseconds,
                url.lastPathComponent
            ))
        } catch {
            Log.write("capture failed: \(error)")
            NSSound.beep()
        }
    }

    private func save(_ png: Data) throws -> URL {
        let directory = Self.archiveDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = ScreenshotNaming.uniqueURL(
            in: directory, fileName: ScreenshotNaming.fileName(for: Date())
        ) { FileManager.default.fileExists(atPath: $0.path) }
        try png.write(to: url, options: .withoutOverwriting)
        return url
    }
}
