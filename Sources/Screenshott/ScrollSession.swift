import AppKit
import CoreMedia
@preconcurrency import ScreenCaptureKit
import ScreenshottCore

/// Streams one region of a display with ScreenCaptureKit and stitches each new frame as
/// it arrives, on its own queue so the main thread stays free for the overlay and the
/// scroll loop. ScreenCaptureKit only sends a frame when the region's pixels change, so a
/// page that sits still costs nothing.
///
/// Everything mutable is touched only on `queue`, except `stream`, which belongs to the
/// main actor.
final class ScrollSession: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    /// What one frame did, for the controller and the preview strip.
    struct Update: @unchecked Sendable {
        let step: ScrollStitcher.Step
        /// Height of the stitch so far, in pixels.
        let height: Int
        /// Rows of the region that move with the content.
        let body: Int
        /// Output rows written since the last preview, and the rows still pending from the
        /// last frame, both shrunk to the strip's width. Nil when the preview is unchanged.
        let preview: Preview?
    }

    struct Preview {
        let written: CGImage?
        let writtenRows: Int
        let pending: CGImage?
        let pendingRows: Int
    }

    struct Result: @unchecked Sendable {
        let image: CGImage?
        let frames: Int
        let accepted: Int
        let header: Int
        let footer: Int
        let scrollerCut: Bool
    }

    /// ScreenCaptureKit's BGRA, opaque.
    static let bitmapInfo = CGBitmapInfo(
        rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    )

    private let queue = DispatchQueue(label: "com.adong.Screenshott.scrolling", qos: .userInteractive)
    private let displayID: CGDirectDisplayID
    private let ignoredColumns: Int
    /// Frame pixels per strip pixel.
    private let previewFactor: CGFloat
    private let onUpdate: @MainActor (Update) -> Void
    private let onStop: @MainActor (Error) -> Void

    private var stitcher = ScrollStitcher()
    private var expectedShift: Int?
    private var colorSpace: CGColorSpace?
    private var frames = 0
    private var sawFirst = false
    private var stopped = false
    private var previewed = 0
    private var lastPreview = ContinuousClock.now
    private var previewOwed = false

    @MainActor private var stream: SCStream?

    /// `ignoredColumns` is the scroller band at the right edge, left out of matching.
    /// `previewFactor` shrinks the frames to the preview strip.
    init(
        displayID: CGDirectDisplayID, ignoredColumns: Int, previewFactor: CGFloat,
        onUpdate: @escaping @MainActor (Update) -> Void, onStop: @escaping @MainActor (Error) -> Void
    ) {
        self.displayID = displayID
        self.ignoredColumns = ignoredColumns
        self.previewFactor = max(previewFactor, 1)
        self.onUpdate = onUpdate
        self.onStop = onStop
    }

    /// Starts streaming `sourceRect` (display points, top-left origin) at `pixelSize`.
    /// Our own windows — the overlay, the strip, thumbnails — are left out, except
    /// `including`, which the README demo uses for the page it scrolls.
    @MainActor
    func start(sourceRect: CGRect, pixelSize: PixelSize, including windowNumbers: Set<Int> = []) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.noDisplay
        }
        let me = ProcessInfo.processInfo.processIdentifier
        let filter = SCContentFilter(
            display: display,
            excludingApplications: content.applications.filter { $0.processID == me },
            exceptingWindows: content.windows.filter { windowNumbers.contains(Int($0.windowID)) }
        )
        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect
        config.width = pixelSize.width
        config.height = pixelSize.height
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 4
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    /// How far the next frames should have moved, in auto mode.
    func expect(shift: Int?) {
        queue.async { self.expectedShift = shift }
    }

    @MainActor
    func stop() async {
        await withCheckedContinuation { done in queue.async { self.stopped = true; done.resume() } }
        try? await stream?.stopCapture()
        stream = nil
    }

    /// The stitched image. Call after `stop()`.
    func result() async -> Result {
        await withCheckedContinuation { done in
            queue.async {
                let space = self.colorSpace ?? CGDisplayCopyColorSpace(self.displayID)
                done.resume(returning: Result(
                    image: self.stitcher.image(colorSpace: space, bitmapInfo: Self.bitmapInfo),
                    frames: self.frames, accepted: self.stitcher.accepted,
                    header: self.stitcher.header, footer: self.stitcher.footer,
                    scrollerCut: self.stitcher.scrollerSeen
                ))
            }
        }
    }

    // MARK: - SCStreamOutput, SCStreamDelegate (on `queue`)

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, !stopped, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: status) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer
        else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer), height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        if !sawFirst {
            sawFirst = true
            colorSpace = CVBufferCopyAttachments(pixelBuffer, .shouldPropagate)
                .flatMap { CVImageBufferCreateColorSpaceFromAttachments($0)?.takeRetainedValue() }
            Log.write("scrolling first frame \(width)x\(height) space=\(colorSpace?.name as String? ?? "display")")
        }
        let frame = ScrollFrame(
            width: width, height: height, bytesPerRow: bytesPerRow,
            pixels: UnsafeRawBufferPointer(start: base, count: bytesPerRow * height),
            ignoringTrailingColumns: ignoredColumns
        )
        frames += 1
        let previous = stitcher.last
        let step = stitcher.add(frame, expectedShift: expectedShift)
        if Self.debugDirectory != nil { debug(frame, step: step, previous: previous) }

        var preview: Preview?
        switch step {
        case .first, .full:
            preview = makePreview()
        case .appended:
            // In manual mode frames come at up to 60 a second; the strip doesn't need all.
            if ContinuousClock.now - lastPreview >= .milliseconds(100) {
                preview = makePreview()
            } else if !previewOwed {
                previewOwed = true
                queue.asyncAfter(deadline: .now() + 0.1) { [self] in
                    guard previewOwed, !stopped else { return }
                    send(Update(step: .unchanged, height: stitcher.height, body: stitcher.bodyHeight, preview: makePreview()))
                }
            }
        case .unchanged, .backward, .lost:
            break
        }
        send(Update(step: step, height: stitcher.height, body: stitcher.bodyHeight, preview: preview))
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor in self.onStop(error) }
    }

    // MARK: - Debugging

    /// `--scroll-debug <dir>` (or `--readme-only scrolling`, next to the shots): writes the
    /// first frame and the first few that didn't fit as PNGs, and logs how each differs
    /// from the last good frame — for finding out why a stitch went wrong.
    private static let debugDirectory: URL? = {
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "--scroll-debug"), arguments.indices.contains(flag + 1) {
            return URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        }
        guard let only = arguments.firstIndex(of: "--readme-only"), arguments.dropFirst(only + 1).first == "scrolling",
              let flag = arguments.firstIndex(of: "--readme-shots"), arguments.indices.contains(flag + 1)
        else { return nil }
        return URL(fileURLWithPath: arguments[flag + 1], isDirectory: true).appendingPathComponent("frames")
    }()
    private var debugWritten = 0

    private func debug(_ frame: ScrollFrame, step: ScrollStitcher.Step, previous: ScrollFrame?) {
        guard let directory = Self.debugDirectory, debugWritten < 4 else { return }
        switch step {
        case .first, .lost: break
        default: return
        }
        debugWritten += 1
        var note = ""
        if let previous, previous.pixels.count == frame.pixels.count {
            var pixels = 0, rows = Set<Int>(), largest = 0
            for i in stride(from: 0, to: frame.pixels.count, by: 4) {
                var differs = false
                for c in 0..<4 {
                    let d = abs(Int(frame.pixels[i + c]) - Int(previous.pixels[i + c]))
                    if d > 0 { differs = true; largest = max(largest, d) }
                }
                if differs {
                    pixels += 1
                    rows.insert(i / frame.bytesPerRow)
                }
            }
            note = " vs last good: \(pixels) px in \(rows.count) rows differ, largest channel step \(largest)"
        }
        let name = "frame-\(frames)-\(step == .first ? "first" : "lost").png"
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let space = colorSpace ?? CGDisplayCopyColorSpace(displayID)
        if let image = ScrollStitcher.image(
            pixels: frame.pixels, width: frame.width, height: frame.height, colorSpace: space, bitmapInfo: Self.bitmapInfo
        ), let png = PNGEncoder.data(from: image, scale: 1) {
            try? png.write(to: directory.appendingPathComponent(name))
        }
        Log.write("scrolling debug \(name)\(note)")
    }

    // MARK: - Private (on `queue`)

    private func send(_ update: Update) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.onUpdate(update) } }
    }

    private func makePreview() -> Preview {
        previewOwed = false
        lastPreview = .now
        let space = colorSpace ?? CGDisplayCopyColorSpace(displayID)
        let width = stitcher.width
        let newRows = previewed..<stitcher.written
        previewed = stitcher.written
        var written: CGImage?
        if !newRows.isEmpty {
            written = ScrollStitcher.image(
                pixels: stitcher.writtenPixels(newRows), width: width, height: newRows.count,
                colorSpace: space, bitmapInfo: Self.bitmapInfo
            ).flatMap { ImageScaling.downscaled($0, by: previewFactor) }
        }
        var pending: CGImage?
        let pendingRows = stitcher.pendingRows
        if let last = stitcher.last, !pendingRows.isEmpty {
            pending = ScrollStitcher.image(
                pixels: Array(last.pixels[(pendingRows.lowerBound * last.bytesPerRow)...]), width: width,
                height: pendingRows.count, colorSpace: space, bitmapInfo: Self.bitmapInfo
            ).flatMap { ImageScaling.downscaled($0, by: previewFactor) }
        }
        return Preview(written: written, writtenRows: newRows.count, pending: pending, pendingRows: pendingRows.count)
    }
}
