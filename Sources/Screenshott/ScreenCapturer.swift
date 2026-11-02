import AppKit
@preconcurrency import ScreenCaptureKit
import ScreenshottCore

enum CaptureError: Error {
    case noDisplay
    case encodeFailed
}

struct Capture {
    let image: CGImage
    let scale: CGFloat
    /// Time spent asking ScreenCaptureKit for the display list vs. grabbing pixels —
    /// split out because the list query is the likely cost to cache in M6.
    let contentQuery: Duration
    let grab: Duration
}

@MainActor
enum ScreenCapturer {
    /// Captures the whole display under the mouse at its native backing resolution.
    static func captureDisplayUnderMouse() async throws -> Capture {
        let screens = NSScreen.screens
        let index = DisplayPicking.index(containing: NSEvent.mouseLocation, in: screens.map(\.frame)) ?? 0
        guard screens.indices.contains(index),
              let displayID = screens[index].deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? CGDirectDisplayID
        else { throw CaptureError.noDisplay }
        let scale = screens[index].backingScaleFactor

        let clock = ContinuousClock()
        let start = clock.now
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.noDisplay
        }
        let listed = clock.now

        let config = SCStreamConfiguration()
        // SCDisplay reports points; ask for backing pixels so Retina stays sharp.
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(display: display, excludingWindows: []),
            configuration: config
        )
        return Capture(image: image, scale: scale, contentQuery: listed - start, grab: clock.now - listed)
    }
}
