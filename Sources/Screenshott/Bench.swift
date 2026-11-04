import AppKit
import Carbon.HIToolbox
@preconcurrency import ScreenCaptureKit
import ScreenshottCore
import UniformTypeIdentifiers

/// `open dist/Screenshott.app --args --bench N` times N captures of each kind with no
/// input and logs p50 / p95 per stage, in milliseconds; scripts/bench.sh runs it. A
/// normal launch never gets here.
///
/// 1. **Grab**: each ScreenCapturer.Strategy on the display under the mouse, interleaved
///    so they all see the same conditions. `query` is M1's path, the baseline.
/// 2. **Full screen**: the ⌘⇧1 path end to end — capture, encode, copy + save — on M1's
///    path and on the automatic one.
/// 3. **Area**: the ⌘⇧2 path from the trigger to the frozen overlay on screen, then Esc —
///    on M1's path, on the cached one (what a capture takes while a thumbnail is up), and
///    on the automatic one.
///
/// Captures go to a temp folder that is deleted afterwards and to a private pasteboard,
/// never to the save folder or the clipboard, and make no sound. The app quits when done.
@MainActor
enum Bench {
    static let runs: Int? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "--bench"), arguments.indices.contains(flag + 1),
              let runs = Int(arguments[flag + 1]), runs > 0
        else { return nil }
        return runs
    }()

    private static let suiteName = "com.adong.Screenshott.bench"
    static let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Screenshott-bench", isDirectory: true)
    static let pasteboard = NSPasteboard(name: NSPasteboard.Name(suiteName))

    /// Settings for a bench run, in their own defaults suite: save to `folder`, no sound,
    /// and no thumbnail (one would switch the next capture to the cached path).
    static let defaults: UserDefaults? = {
        guard runs != nil, let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        let settings = Preferences(defaults: defaults)
        settings.saveDirectory = folder
        settings.copyToClipboard = true
        settings.keepRetinaResolution = true
        settings.playSound = false
        settings.showThumbnail = false
        return defaults
    }()

    static func cleanUp() {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.count ?? 0
        try? FileManager.default.removeItem(at: folder)
        pasteboard.releaseGlobally()
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        Log.write("bench wrote \(files) file(s) to \(folder.path), deleted")
    }

    static let escape = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
        characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: UInt16(kVK_Escape)
    )

    /// Timings grouped as section → variant → stage, printed in the order first seen.
    struct Report {
        private var rows: [(key: String, samples: [Double])] = []
        private var failures: [String: [String]] = [:]

        mutating func add(_ section: String, _ variant: String, _ stage: String, _ duration: Duration) {
            let key = [section, variant, stage].map { $0.padding(toLength: 12, withPad: " ", startingAt: 0) }.joined()
            if let index = rows.firstIndex(where: { $0.key == key }) {
                rows[index].samples.append(duration.milliseconds)
            } else {
                rows.append((key, [duration.milliseconds]))
            }
        }

        mutating func add(_ section: String, _ variant: String, _ samples: [Perf.Stage: [Duration]]) {
            for stage in Perf.Stage.allCases {
                for duration in samples[stage] ?? [] { add(section, variant, stage.rawValue, duration) }
            }
        }

        mutating func fail(_ section: String, _ variant: String, _ error: Any) {
            failures["\(section) \(variant)", default: []].append("\(error)")
        }

        func write() {
            for row in rows {
                if let stats = BenchStats(row.samples) { Log.write("bench \(row.key)\(stats.summary)") }
            }
            for (key, errors) in failures.sorted(by: { $0.key < $1.key }) {
                Log.write("bench \(key) failed \(errors.count)x: \(errors.first ?? "")")
            }
        }
    }
}

extension Bench {
    /// Whether the WindowServer lists `window` as on screen — it has the window's
    /// first frame and composites it at the next display refresh.
    static func isOnScreen(_ window: NSWindow) -> Bool {
        let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(window.windowNumber)) as? [[String: Any]]
        return info?.first?[kCGWindowIsOnscreen as String] as? Bool ?? false
    }
}

extension AppDelegate {
    func runBench(runs: Int) async {
        delivery.pasteboard = Bench.pasteboard
        defer {
            ScreenCapturer.forcedStrategy = nil
            Perf.samples = nil
            Bench.cleanUp()
            Log.write("bench done")
            NSApp.terminate(nil)
        }
        // Let the launch settle and the content cache fill.
        try? await Task.sleep(for: .seconds(1.5))
        guard Permissions.hasScreenCapture, let screen = ScreenCapturer.screenUnderMouse else {
            Log.write("bench: needs the Screen Recording grant and a display")
            return
        }
        let points = screen.frame.size, scale = screen.backingScaleFactor
        Log.write(String(
            format: "bench %d runs on %.0fx%.0f @%.0fx (%d display(s)), %@",
            runs, points.width * scale, points.height * scale, scale, NSScreen.screens.count,
            ProcessInfo.processInfo.operatingSystemVersionString
        ))
        var report = Bench.Report()
        // Our menu open stalls every MainActor task, so a run it interrupts is skewed.
        var menuOpened = 0
        let menuObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { menuOpened += 1 } }
        defer { NotificationCenter.default.removeObserver(menuObserver) }

        // 1. Grab paths, one of each per round.
        let strategies = ScreenCapturer.Strategy.allCases.filter(\.isAvailable)
        for round in 0..<runs {
            for strategy in strategies {
                ScreenCapturer.forcedStrategy = strategy
                do {
                    let capture = try await ScreenCapturer.capture([screen], excluding: [])
                    if round == 0 {
                        Log.write(String(
                            format: "bench first %@ after launch: list=%.1fms grab=%.1fms", strategy.rawValue,
                            capture.contentQuery.milliseconds, capture.grab.milliseconds
                        ))
                    }
                    report.add("grab", strategy.rawValue, "content list", capture.contentQuery)
                    report.add("grab", strategy.rawValue, "grab", capture.grab)
                    report.add("grab", strategy.rawValue, "total", capture.contentQuery + capture.grab)
                    if strategy == .query, let display = capture.displays.first {
                        Bench.encodeVariants(display.image, scale: display.scale, logSizes: round == 0, into: &report)
                    }
                } catch {
                    report.fail("grab", strategy.rawValue, error)
                }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        await checkCapturePaths(on: screen)

        // 2. ⌘⇧1 end to end.
        for _ in 0..<runs {
            for strategy in [ScreenCapturer.Strategy.query, nil] {
                ScreenCapturer.forcedStrategy = strategy
                let variant = strategy?.rawValue ?? "automatic"
                Perf.samples = [:]
                let start = ContinuousClock.now
                await runFullScreenCapture()
                report.add("full screen", variant, "trigger → saved", .now - start)
                report.add("full screen", variant, Perf.samples ?? [:])
                Perf.samples = nil
                try? await Task.sleep(for: .milliseconds(250))
            }
        }

        // 3. ⌘⇧2 up to the overlay on screen, then Esc.
        for _ in 0..<runs {
            for strategy in [ScreenCapturer.Strategy.query, .cached, nil] {
                await benchAreaCapture(strategy, idle: .milliseconds(400), into: &report)
            }
        }

        // 4. The same after the Mac sat idle, as a real press usually is.
        for _ in 0..<3 {
            await benchAreaCapture(nil, idle: .seconds(10), into: &report)
        }
        report.write()
        if menuOpened > 0 {
            Log.write("bench disturbed: the menu bar menu was opened \(menuOpened)x during the run; timings are skewed")
        }
    }

    /// One ⌘⇧2 after `idle`: trigger → overlay shown (our main-thread work done) →
    /// on screen (the WindowServer has it), then Esc.
    private func benchAreaCapture(_ strategy: ScreenCapturer.Strategy?, idle: Duration, into report: inout Bench.Report) async {
        try? await Task.sleep(for: idle)
        ScreenCapturer.forcedStrategy = strategy
        let section = idle > .seconds(1) ? "area idle" : "area"
        let variant = strategy?.rawValue ?? "automatic"
        Perf.samples = [:]
        defer { Perf.samples = nil }
        let pressed = ContinuousClock.now
        await runAreaCapture(pressedAt: pressed)
        let shown = ContinuousClock.now - pressed
        guard let overlay, let escape = Bench.escape else {
            report.fail(section, variant, "overlay did not open")
            return
        }
        let panels = NSApp.windows.filter { $0 is OverlayPanel && $0.isVisible }
        var onScreen: Duration?
        for _ in 0..<500 {
            if panels.contains(where: Bench.isOnScreen) {
                onScreen = .now - pressed
                break
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        report.add(section, variant, Perf.samples ?? [:])
        report.add(section, variant, "→ shown", shown)
        if let onScreen {
            report.add(section, variant, "→ on screen", onScreen)
        } else {
            report.fail(section, variant, "the WindowServer never listed the overlay as on screen")
        }
        overlay.handleKey(escape)
    }

    /// One-off checks behind the timings, logged as `bench check …`:
    /// - the cached content still captures a window that opened after it was fetched,
    ///   so other apps' windows really don't need a new query;
    /// - whether `captureImage(in:)`, which has no cursor setting, draws the cursor.
    private func checkCapturePaths(on screen: NSScreen) async {
        let side: CGFloat = 160
        let probe = NSWindow(
            contentRect: CGRect(x: screen.frame.midX - side / 2, y: screen.frame.midY - side / 2, width: side, height: side),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        probe.isReleasedWhenClosed = false
        probe.level = .floating
        let view = NSView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1).cgColor
        probe.contentView = view
        probe.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(300))
        var centers: [String] = []
        for strategy in [ScreenCapturer.Strategy.cached, .query, .rect] where strategy.isAvailable {
            ScreenCapturer.forcedStrategy = strategy
            guard let image = try? await ScreenCapturer.capture([screen], excluding: []).displays.first?.image else {
                centers.append("\(strategy)=failed")
                continue
            }
            let rgba = Bench.patch(of: image, around: CGPoint(x: image.width / 2, y: image.height / 2), side: 1)
            centers.append("\(strategy)=\(rgba.map { Array($0) } ?? [])")
        }
        probe.orderOut(nil)
        Log.write("bench check: centre pixel with a magenta window opened after the cache was filled: \(centers.joined(separator: " "))")
        try? await Task.sleep(for: .milliseconds(300))

        // The cursor: a filter capture with it and one without are the controls.
        guard let id = screen.displayID,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == id })
        else { return }
        let mouse = NSEvent.mouseLocation, frame = screen.frame, scale = screen.backingScaleFactor
        let pointer = CGPoint(x: (mouse.x - frame.minX) * scale, y: (frame.maxY - mouse.y) * scale)
        var patches: [String: Data] = [:]
        for cursor in [false, true] {
            let config = SCStreamConfiguration()
            config.width = Int(CGFloat(display.width) * scale)
            config.height = Int(CGFloat(display.height) * scale)
            config.showsCursor = cursor
            let filter = SCContentFilter(display: display, excludingWindows: [])
            if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                patches[cursor ? "with" : "without"] = Bench.patch(of: image, around: pointer, side: Int(48 * scale))
            }
        }
        if #available(macOS 15.2, *), let image = try? await SCScreenshotManager.captureImage(in: CGDisplayBounds(id)) {
            patches["rect"] = Bench.patch(of: image, around: pointer, side: Int(48 * scale))
        }
        let visible = patches["with"] != patches["without"]
        let rect = patches["rect"].map { $0 == patches["without"] ? "no" : $0 == patches["with"] ? "yes" : "unclear" } ?? "n/a"
        Log.write("bench check: cursor showing during the check: \(visible ? "yes" : "no (inconclusive)"); captureImage(in:) draws it: \(rect)")
    }
}

extension Bench {
    /// Delivery ideas, measured on a fresh capture: what PNG costs the first time the
    /// image is read and again, what cheaper PNG filters and uncompressed TIFF cost.
    static func encodeVariants(_ image: CGImage, scale: CGFloat, logSizes: Bool, into report: inout Report) {
        let variants: [(String, () -> Data?)] = [
            ("png", { PNGEncoder.data(from: image, scale: scale) }),
            ("png again", { PNGEncoder.data(from: image, scale: scale) }),
            ("png sub", { encode(image, as: .png, filter: IMAGEIO_PNG_FILTER_SUB) }),
            ("png none", { encode(image, as: .png, filter: IMAGEIO_PNG_FILTER_NONE) }),
            ("tiff", { encode(image, as: .tiff, filter: nil) }),
        ]
        var sizes: [String] = []
        for (name, encode) in variants {
            let start = ContinuousClock.now
            let data = encode()
            report.add("encode", name, "", .now - start)
            sizes.append("\(name)=\((data?.count ?? 0) / 1024)KB")
        }
        if logSizes { Log.write("bench check: encoded sizes \(sizes.joined(separator: " "))") }
    }

    private static func encode(_ image: CGImage, as type: UTType, filter: Int32?) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            return nil
        }
        var properties: [CFString: Any] = [:]
        if let filter {
            properties[kCGImagePropertyPNGCompressionFilter] = filter
            properties[kCGImagePropertyPNGDictionary] = [kCGImagePropertyPNGCompressionFilter: filter]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    /// RGBA bytes of the `side`-pixel square of `image` around `center` (top-left pixel
    /// coordinates), redrawn into sRGB so two captures compare byte for byte.
    static func patch(of image: CGImage, around center: CGPoint, side: Int) -> Data? {
        let rect = CGRect(x: center.x - CGFloat(side / 2), y: center.y - CGFloat(side / 2), width: CGFloat(side), height: CGFloat(side))
            .integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !rect.isEmpty, let crop = image.cropping(to: rect),
              let context = CGContext(
                  data: nil, width: crop.width, height: crop.height, bitsPerComponent: 8, bytesPerRow: crop.width * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        guard let bytes = context.data else { return nil }
        return Data(bytes: bytes, count: crop.height * crop.width * 4)
    }
}
