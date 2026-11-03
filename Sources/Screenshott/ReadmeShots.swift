import AppKit
import ScreenshottCore

/// `open dist/Screenshott.app --args --readme-shots <dir>` drives the area overlay, the
/// thumbnail and Settings without a mouse and writes a cropped PNG of each to `<dir>`, ready for
/// docs/images. scripts/readme-shots.sh runs it. A normal launch never gets here.
///
/// Everything happens over a stock macOS wallpaper, so the shots never contain what was
/// really on screen.
///
/// The menu bar menu isn't shot: on macOS 26 the status item is drawn by the system, and
/// `performClick` opens our menu beside an off-screen stand-in window (2026-11-02).
@MainActor
enum ReadmeShots {
    static var directory: URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "--readme-shots"), arguments.indices.contains(flag + 1) else {
            return nil
        }
        return URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
    }

    private static let wallpapers = ["Sonoma.heic", "Mac Purple.heic"].map {
        URL(fileURLWithPath: "/System/Library/Desktop Pictures").appendingPathComponent($0)
    }

    /// A borderless window over the whole display showing the wallpaper. Floating, so
    /// re-activating the previous app can't bring its windows over it, and the
    /// thumbnail (also floating, ordered later) still lands on top.
    static func backdrop(on screen: NSScreen) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(red: 0.36, green: 0.25, blue: 0.94, alpha: 1).cgColor
        view.layer?.contents = wallpapers.lazy.compactMap { NSImage(contentsOf: $0) }.first
        view.layer?.contentsGravity = .resizeAspectFill
        window.contentView = view
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        return window
    }

    /// `region` (Cocoa global points) of `screen`, our own windows included — they are
    /// the subject.
    static func photograph(_ region: CGRect, of screen: NSScreen, as name: String, in directory: URL) async {
        do {
            let capture = try await ScreenCapturer.capture([screen], excluding: [])
            guard let display = capture.displays.first else { throw CaptureError.noDisplay }
            let frame = screen.frame
            let r = region.intersection(frame)
            let crop = CGRect(
                x: (r.minX - frame.minX) * display.scale, y: (frame.maxY - r.maxY) * display.scale,
                width: r.width * display.scale, height: r.height * display.scale
            ).integral
            guard let image = display.image.cropping(to: crop),
                  let png = PNGEncoder.data(from: image, scale: display.scale)
            else { throw CaptureError.encodeFailed }
            try png.write(to: directory.appendingPathComponent(name))
            Log.write("readme-shots wrote \(name) \(image.width)x\(image.height)")
        } catch {
            Log.write("readme-shots \(name) failed: \(error)")
        }
    }
}

extension AppDelegate {
    func runReadmeShots(into directory: URL) async {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            Log.write("readme-shots: can't create \(directory.path): \(error)")
            return
        }
        // Let the launch settle (status item placed, permission state read).
        try? await Task.sleep(for: .seconds(1.5))
        guard let stage = ScreenCapturer.screenUnderMouse ?? NSScreen.screens.first else { return }
        let backdrop = ReadmeShots.backdrop(on: stage)
        defer {
            backdrop.orderOut(nil)
            Log.write("readme-shots done: \(directory.path)")
        }
        try? await Task.sleep(for: .milliseconds(400))

        // 1. The frozen overlay with a staged selection and the loupe on its corner. The
        // crop leaves room for the size label above and the loupe below right.
        await runAreaCapture(pressedAt: ContinuousClock.now)
        guard let overlay, let screen = overlay.stageForReadme(),
              let view = overlay.selectionView, let selection = view.target
        else {
            Log.write("readme-shots: overlay did not open")
            return
        }
        let hole = view.geometry.viewRect(for: selection).offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        try? await Task.sleep(for: .milliseconds(600))
        await ReadmeShots.photograph(
            CGRect(x: hole.minX - 60, y: hole.minY - 230, width: hole.width + 280, height: hole.height + 300),
            of: screen, as: "overlay.png", in: directory
        )

        // 2. Enter: copy + archive + the floating thumbnail in the bottom-right corner.
        overlay.confirm(.standard)
        try? await Task.sleep(for: .milliseconds(1200))
        let visible = screen.visibleFrame
        await ReadmeShots.photograph(
            CGRect(x: visible.maxX - 380, y: visible.minY, width: 380, height: 240),
            of: screen, as: "thumbnail.png", in: directory
        )

        // 3. Settings, lifted to the backdrop's level so it shows above it.
        openSettings()
        guard let window = settingsWindow else { return }
        window.level = .floating
        window.setFrameOrigin(CGPoint(
            x: screen.frame.midX - window.frame.width / 2, y: screen.frame.midY - window.frame.height / 2
        ))
        window.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(800))
        await ReadmeShots.photograph(window.frame.insetBy(dx: -40, dy: -40), of: screen, as: "settings.png", in: directory)
        window.level = .normal
        window.close()
    }
}
