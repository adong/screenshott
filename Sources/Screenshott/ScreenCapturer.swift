import AppKit
@preconcurrency import ScreenCaptureKit
import ScreenshottCore

enum CaptureError: Error {
    case noDisplay
    case encodeFailed
    /// A rect capture came back at another size than the display's backing pixels.
    case unexpectedSize(width: Int, height: Int)
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
    /// Time spent getting ScreenCaptureKit's display and window list vs. grabbing
    /// pixels. Since M6 the list is cached or not needed, so it is close to zero.
    let contentQuery: Duration
    let grab: Duration
    let strategy: ScreenCapturer.Strategy
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
    /// How the pixels are fetched. Each capture picks one (`strategy(excluding:)`); the
    /// bench forces each in turn to time them against each other.
    enum Strategy: String, CaseIterable {
        /// M1: ask for SCShareableContent on every capture, then capture through a
        /// display filter that leaves our thumbnails out.
        case query
        /// The same filter capture, with the content from ShareableContentCache.
        case cached
        /// macOS 15.2 `captureImage(in:)`: no content needed at all, but it can't leave
        /// windows out, so only while no thumbnail is up. It has no cursor setting; the
        /// bench checks that it leaves the cursor out (it does on macOS 26.7).
        case rect
        /// macOS 26 `captureScreenshot(rect:)`, the same with a configuration. Slower
        /// than `rect` and sometimes fails to start (-3811), so only the bench uses it.
        case rect26

        var isAvailable: Bool {
            switch self {
            case .query, .cached:
                return true
            case .rect:
                if #available(macOS 15.2, *) { return true }
                return false
            case .rect26:
                if #available(macOS 26.0, *) { return true }
                return false
            }
        }
    }

    /// Set by the bench to time one strategy; nil lets each capture pick.
    static var forcedStrategy: Strategy?
    /// Off once a rect capture fails on this Mac — a display it sizes differently, say;
    /// captures then stay on the filter path until the next launch.
    private static var rectWorks = true

    static func strategy(excluding windowNumbers: Set<Int>) -> Strategy {
        windowNumbers.isEmpty && rectWorks && Strategy.rect.isAvailable ? .rect : .cached
    }

    static var screenUnderMouse: NSScreen? {
        let screens = NSScreen.screens
        return DisplayPicking.index(containing: NSEvent.mouseLocation, in: screens.map(\.frame)).map { screens[$0] }
    }

    /// Captures each of `screens` at its native backing resolution, all at the same
    /// time. Windows numbered in `windowNumbers` — our own thumbnails — are left out of
    /// the pixels. (Excluding the whole app would also cut our menu bar icon out.)
    static func capture(_ screens: [NSScreen], excluding windowNumbers: Set<Int>) async throws -> FrozenCapture {
        if let forcedStrategy {
            return try await capture(screens, excluding: windowNumbers, using: forcedStrategy)
        }
        // A rect API acting up falls back to the cache, a stale cache to M1's path.
        var strategy = strategy(excluding: windowNumbers)
        while true {
            do {
                return try await capture(screens, excluding: windowNumbers, using: strategy)
            } catch {
                let next: Strategy
                switch strategy {
                case .rect, .rect26:
                    rectWorks = false
                    next = .cached
                case .cached:
                    ShareableContentCache.refresh()
                    next = .query
                case .query:
                    throw error
                }
                Log.write("capture via \(strategy) failed (\(error)); trying \(next)")
                strategy = next
            }
        }
    }

    private enum Job {
        case filter(SCContentFilter, SCStreamConfiguration)
        /// `rect` in global CoreGraphics points; `pixels` is what the display's backing
        /// store holds there. `configurable` picks the macOS 26 API.
        case rect(CGRect, pixels: PixelSize, configurable: Bool)
    }

    private static func capture(
        _ screens: [NSScreen], excluding windowNumbers: Set<Int>, using strategy: Strategy
    ) async throws -> FrozenCapture {
        let list = Perf.begin(.contentList)
        var content: SCShareableContent?
        switch strategy {
        case .query: content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        case .cached: content = try await ShareableContentCache.content(listing: windowNumbers)
        case .rect, .rect26: content = nil
        }
        let excluded = content?.windows.filter { windowNumbers.contains(Int($0.windowID)) } ?? []
        let contentQuery = Perf.end(list)

        var jobs: [Unchecked<Job>] = []
        var targets: [(screen: NSScreen, id: CGDirectDisplayID)] = []
        for screen in screens {
            guard let id = screen.displayID else { continue }
            if let content {
                guard let display = content.displays.first(where: { $0.displayID == id }) else { continue }
                let config = SCStreamConfiguration()
                // SCDisplay reports points; ask for backing pixels so Retina stays sharp.
                config.width = Int(CGFloat(display.width) * screen.backingScaleFactor)
                config.height = Int(CGFloat(display.height) * screen.backingScaleFactor)
                config.showsCursor = false
                jobs.append(Unchecked(value: .filter(SCContentFilter(display: display, excludingWindows: excluded), config)))
            } else {
                let bounds = CGDisplayBounds(id)
                let pixels = PixelSize(
                    width: Int(bounds.width * screen.backingScaleFactor),
                    height: Int(bounds.height * screen.backingScaleFactor)
                )
                jobs.append(Unchecked(value: .rect(bounds, pixels: pixels, configurable: strategy == .rect26)))
            }
            targets.append((screen, id))
        }
        guard !jobs.isEmpty else { throw CaptureError.noDisplay }

        let grab = Perf.begin(.grab)
        let images = try await withThrowingTaskGroup(of: (Int, Unchecked<CGImage>).self) { group in
            for (index, job) in jobs.enumerated() {
                group.addTask { (index, Unchecked(value: try await image(for: job.value))) }
            }
            var images: [Int: CGImage] = [:]
            for try await (index, image) in group { images[index] = image.value }
            return images
        }
        let grabbed = Perf.end(grab)

        let displays = targets.enumerated().compactMap { index, target in
            images[index].map {
                FrozenDisplay(screen: target.screen, displayBounds: CGDisplayBounds(target.id), image: $0)
            }
        }
        return FrozenCapture(displays: displays, contentQuery: contentQuery, grab: grabbed, strategy: strategy)
    }

    nonisolated private static func image(for job: Job) async throws -> CGImage {
        switch job {
        case let .filter(filter, config):
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        case let .rect(rect, pixels, configurable):
            var image: CGImage?
            if configurable, #available(macOS 26.0, *) {
                let config = SCScreenshotConfiguration()
                config.width = pixels.width
                config.height = pixels.height
                config.showsCursor = false
                config.dynamicRange = .sdr
                image = try await SCScreenshotManager.captureScreenshot(rect: rect, configuration: config).sdrImage
            } else if #available(macOS 15.2, *) {
                image = try await SCScreenshotManager.captureImage(in: rect)
            }
            guard let image else { throw CaptureError.noDisplay }
            // These APIs pick the output size themselves; a frame at the wrong scale
            // would crop wrong in the overlay.
            guard image.width == pixels.width, image.height == pixels.height else {
                throw CaptureError.unexpectedSize(width: image.width, height: image.height)
            }
            return image
        }
    }
}

/// SCShareableContent takes 20–35 ms to fetch, a quarter of a capture, and a capture
/// needs little of it: the SCDisplay of each screen, and the SCWindows of our own
/// thumbnails to leave them out. Other apps' windows don't matter — a display filter
/// captures whatever is on the display, windows opened after the query included. So
/// the content is fetched ahead of time and kept until the displays change or the Mac
/// wakes, and fetched again when a thumbnail appears.
@MainActor
enum ShareableContentCache {
    private static var fetch: Task<Unchecked<SCShareableContent>, Error>?
    private static var observers: [NSObjectProtocol] = []

    /// Starts watching for display changes and fetches the first copy. Only call it
    /// with the Screen Recording grant: without it the query raises the system prompt.
    static func start() {
        guard observers.isEmpty else { return }
        let changed: @Sendable (Notification) -> Void = { _ in MainActor.assumeIsolated { refresh() } }
        observers = [
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: changed
            ),
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: changed
            ),
        ]
        refresh()
    }

    /// Drops the cached copy and fetches a new one in the background.
    static func refresh() {
        _ = refetch()
    }

    private static func refetch() -> Task<Unchecked<SCShareableContent>, Error> {
        let task = Task { Unchecked(value: try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)) }
        fetch = task
        return task
    }

    /// The cached content, or a fresh copy when there is none, the last fetch failed,
    /// or it doesn't list every window in `windowNumbers` (a thumbnail newer than it).
    static func content(listing windowNumbers: Set<Int>) async throws -> SCShareableContent {
        if let fetch, let content = try? await fetch.value.value,
           windowNumbers.isSubset(of: content.windows.map { Int($0.windowID) }) {
            return content
        }
        return try await refetch().value.value
    }
}

@MainActor
enum WindowList {
    /// On-screen app windows, front to back, in global CoreGraphics points. Taken
    /// before the overlay goes up, so it never lists the overlay itself.
    static func snapshot() -> [CGRect] {
        let span = Perf.begin(.windowList)
        defer { Perf.end(span) }
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
