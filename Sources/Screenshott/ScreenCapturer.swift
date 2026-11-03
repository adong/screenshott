import AppKit
@preconcurrency import ScreenCaptureKit
import ScreenshottCore

enum CaptureError: Error {
    case noDisplay
    case encodeFailed
}

/// One display, frozen at the moment the hotkey fired.
struct FrozenDisplay {
    let screen: NSScreen
    /// The display in global CoreGraphics points (top-left origin) — the space window
    /// bounds come in.
    let displayBounds: CGRect
    let image: CGImage

    var geometry: OverlayGeometry {
        OverlayGeometry(
            pointSize: screen.frame.size, pixelSize: PixelSize(width: image.width, height: image.height)
        )
    }

    var scale: CGFloat { geometry.scale }
}

struct FrozenCapture {
    let displays: [FrozenDisplay]
    /// Time spent asking ScreenCaptureKit for the display list vs. grabbing pixels —
    /// split out because the list query is the likely cost to cache in M6.
    let contentQuery: Duration
    let grab: Duration
}

/// CGImage and ScreenCaptureKit's request objects are immutable once built, so passing
/// them between tasks is safe even though the SDK doesn't mark them Sendable.
private struct Unchecked<Value>: @unchecked Sendable {
    let value: Value
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

@MainActor
enum ScreenCapturer {
    static var screenUnderMouse: NSScreen? {
        let screens = NSScreen.screens
        return DisplayPicking.index(containing: NSEvent.mouseLocation, in: screens.map(\.frame)).map { screens[$0] }
    }

    /// Captures each of `screens` at its native backing resolution, all at the same
    /// time. Windows numbered in `windowNumbers` — our own thumbnails — are left out of
    /// the pixels. (Excluding the whole app would also cut our menu bar icon out.)
    static func capture(_ screens: [NSScreen], excluding windowNumbers: Set<Int>) async throws -> FrozenCapture {
        let clock = ContinuousClock()
        let start = clock.now
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let excluded = content.windows.filter { windowNumbers.contains(Int($0.windowID)) }
        let listed = clock.now

        var jobs: [Unchecked<(SCContentFilter, SCStreamConfiguration)>] = []
        var targets: [(screen: NSScreen, id: CGDirectDisplayID)] = []
        for screen in screens {
            guard let id = screen.displayID,
                  let display = content.displays.first(where: { $0.displayID == id })
            else { continue }
            let config = SCStreamConfiguration()
            // SCDisplay reports points; ask for backing pixels so Retina stays sharp.
            config.width = Int(CGFloat(display.width) * screen.backingScaleFactor)
            config.height = Int(CGFloat(display.height) * screen.backingScaleFactor)
            config.showsCursor = false
            jobs.append(Unchecked(value: (SCContentFilter(display: display, excludingWindows: excluded), config)))
            targets.append((screen, id))
        }
        guard !jobs.isEmpty else { throw CaptureError.noDisplay }

        let images = try await withThrowingTaskGroup(of: (Int, Unchecked<CGImage>).self) { group in
            for (index, job) in jobs.enumerated() {
                group.addTask {
                    let (filter, config) = job.value
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    return (index, Unchecked(value: image))
                }
            }
            var images: [Int: CGImage] = [:]
            for try await (index, image) in group { images[index] = image.value }
            return images
        }

        let displays = targets.enumerated().compactMap { index, target in
            images[index].map {
                FrozenDisplay(screen: target.screen, displayBounds: CGDisplayBounds(target.id), image: $0)
            }
        }
        return FrozenCapture(displays: displays, contentQuery: listed - start, grab: clock.now - listed)
    }
}

enum WindowList {
    /// On-screen app windows, front to back, in global CoreGraphics points. Taken
    /// before the overlay goes up, so it never lists the overlay itself.
    static func snapshot() -> [CGRect] {
        guard let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }
        let me = ProcessInfo.processInfo.processIdentifier
        return info.compactMap { window in
            // Layer 0 is ordinary app windows: no menu bar, Dock or status items.
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  (window[kCGWindowOwnerPID as String] as? pid_t) != me,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width >= 20, rect.height >= 20
            else { return nil }
            return rect
        }
    }
}
