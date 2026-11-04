import CoreGraphics
import Foundation

/// How far the content moved between two frames of the same region, and which rows
/// stayed put. Vertical only: content moving up means the view scrolled down.
public struct FrameMatch: Equatable, Sendable {
    /// Rows the content moved up from the previous frame to the next; negative when
    /// it moved down (scrolled back up), 0 when nothing moved.
    public let shift: Int
    /// Rows at the top that are the same in both frames at the same place: a sticky
    /// header, a toolbar, or blank space that happens to agree.
    public let header: Int
    /// The same at the bottom: a sticky footer or a message box.
    public let footer: Int
}

public enum OverlapSearch {
    /// Sticky bands are cut off at this share of the frame each, so a mostly blank
    /// frame can't swallow the part that moves.
    static let maxStickyShare = 0.4
    /// With no shift that fits, a frame where at most this share of the non-blank rows
    /// changed counts as unchanged (an animation played); more, and the overlap is lost.
    static let maxChangedShareForUnchanged = 0.25

    /// Matches `next` against `previous`, or nil when no shift lines them up.
    ///
    /// Rows are compared by hash. A shift is scored by the non-blank rows it lines up,
    /// minus four for each row it gets wrong; a few wrong rows (a caret, a spinner) are
    /// forgiven, many are not. Not moving at all competes on the same rows, with rows
    /// that differ by a few pixels counted as equal. `expected` is how far we scrolled,
    /// in auto mode; it picks between shifts that fit equally cleanly.
    public static func match(_ previous: ScrollFrame, _ next: ScrollFrame, expected: Int? = nil) -> FrameMatch? {
        guard previous.width == next.width, previous.height == next.height else { return nil }
        let height = next.height
        let tolerance = max(2, next.matchWidth / 100)

        // Which rows are (nearly) the same at the same place.
        var still = [Bool](repeating: false, count: height)
        var changed = 0, informative = 0
        for i in 0..<height {
            still[i] = next.row(i, nearlyEquals: i, of: previous, tolerance: tolerance)
            if !still[i] { changed += 1 }
            if !(next.uniformRows[i] && previous.uniformRows[i]) { informative += 1 }
        }
        if changed == 0 { return FrameMatch(shift: 0, header: 0, footer: 0) }

        let cap = Int(Double(height) * maxStickyShare)
        let header = min(still.prefix { $0 }.count, cap)
        let footer = min(still.reversed().prefix { $0 }.count, cap)
        // Body rows [top, bottom) of both frames; next's row i shows previous's row i + shift.
        let top = header, bottom = height - footer
        let body = bottom - top
        let minOverlap = max(8, body / 20)

        var stillScore = 0
        for i in top..<bottom {
            if still[i] {
                if !next.uniformRows[i] { stillScore += 1 }
            } else if !(next.uniformRows[i] && previous.uniformRows[i]) {
                stillScore -= 4
            }
        }

        var candidates: [(shift: Int, score: Int, clean: Bool)] = []
        if body > minOverlap, next.bands == previous.bands {
            let bands = next.bands, slack = next.bandTolerance
            next.rowHashes.withUnsafeBufferPointer { n in
                previous.rowHashes.withUnsafeBufferPointer { p in
                    next.bandSums.withUnsafeBufferPointer { ns in
                        previous.bandSums.withUnsafeBufferPointer { ps in
                            // ScrollFrame.row(_:matches:of:), unrolled: this runs for every shift.
                            func same(_ i: Int, _ j: Int) -> Bool {
                                if n[i] == p[j] { return true }
                                for k in 0..<bands where abs(ns[i * bands + k] - ps[j * bands + k]) > slack { return false }
                                return true
                            }
                            for shift in -(body - minOverlap)...(body - minOverlap) where shift != 0 {
                                let from = max(top, top - shift), to = min(bottom, bottom - shift)
                                let allowed = 2 + (to - from) / 10
                                var matches = 0, misses = 0
                                for i in from..<to {
                                    let j = i + shift
                                    if same(i, j) {
                                        if !next.uniformRows[i] { matches += 1 }
                                    } else if !(next.uniformRows[i] && previous.uniformRows[j]) {
                                        misses += 1
                                        if misses > allowed { break }
                                    }
                                }
                                guard misses <= allowed, matches >= 3 else { continue }
                                candidates.append((shift, matches - 4 * misses, misses * 30 <= matches))
                            }
                        }
                    }
                }
            }
        }
        // Content that repeats (a list of identical rows) lines up at several shifts. The
        // smallest has the most overlap and wins on score, but when we know how far we
        // scrolled, the clean fit nearest that is the likelier one.
        let clean = candidates.filter(\.clean)
        let best = if let expected, !clean.isEmpty {
            clean.min { abs($0.shift - expected) < abs($1.shift - expected) }
        } else {
            // Ties go to the smaller shift, and to down over up: that's the way we scroll.
            candidates.min { a, b in
                if a.score != b.score { return a.score > b.score }
                return abs(a.shift) != abs(b.shift) ? abs(a.shift) < abs(b.shift) : a.shift > b.shift
            }
        }

        let stillPlausible = Double(changed) <= maxChangedShareForUnchanged * Double(max(informative, 1))
        if let best, best.score > stillScore || !stillPlausible {
            return FrameMatch(shift: best.shift, header: header, footer: footer)
        }
        return stillPlausible ? FrameMatch(shift: 0, header: header, footer: footer) : nil
    }
}

/// Builds one tall image out of frames of a region that scrolls under it.
///
/// Content rows are numbered from the top of the first frame. Each accepted frame sits
/// at an offset: how far the content has moved up since the first. A frame's rows are
/// written once the next frame tells us which of its bottom rows are a sticky footer;
/// the last frame is written whole at the end. So the header comes from the first
/// frame only and the footer from the last only, and guessing the footer too big (blank
/// rows that happened to agree) only delays rows, never loses them — the next frame
/// continues exactly where the written part ends.
public struct ScrollStitcher: Sendable {
    public enum Step: Equatable, Sendable {
        /// The first frame; nothing to compare it with yet.
        case first
        /// The content moved up by `shift` rows and the output grew.
        case appended(shift: Int)
        /// Nothing moved (or only a caret blinked).
        case unchanged
        /// The content moved down: someone scrolled back up. Ignored.
        case backward(shift: Int)
        /// No overlap with the last good frame: scrolled too far between frames, or the
        /// content changed. Ignored; the next frame is compared with the same one.
        case lost
        /// Taking this frame would pass `maxHeight`, so it was left out and the capture
        /// should stop.
        case full
    }

    public static let defaultMaxHeight = 30_000

    public let maxHeight: Int
    public private(set) var width = 0
    /// Rows written so far: content rows [0, written).
    public private(set) var written = 0
    /// The last accepted frame and its offset; its rows from `written - offset` down
    /// are still to be written.
    public private(set) var last: ScrollFrame?
    public private(set) var offset = 0
    /// The latest pair's sticky bands, for the log and for sizing the next scroll.
    public private(set) var header = 0
    public private(set) var footer = 0
    public private(set) var accepted = 0
    /// Something moved in the scroller band between frames — the scroller itself, at a
    /// different place in each frame. Then the band is cut off the output, or it would
    /// show a piece of scroller at every seam.
    public private(set) var scrollerSeen = false
    private var canvas: [UInt8] = []

    public init(maxHeight: Int = defaultMaxHeight) {
        self.maxHeight = maxHeight
    }

    /// Height of the image `image` would make now: everything written plus the rest of
    /// the last frame.
    public var height: Int { last.map { offset + $0.height } ?? 0 }

    /// The last frame's rows that are not written yet — what the end adds.
    public var pendingRows: Range<Int> {
        guard let last else { return 0..<0 }
        return (written - offset)..<last.height
    }

    /// Rows of the last frame that move with the content.
    public var bodyHeight: Int { last.map { $0.height - header - footer } ?? 0 }

    public mutating func add(_ frame: ScrollFrame, expectedShift: Int? = nil) -> Step {
        guard let previous = last else {
            last = frame
            width = frame.width
            accepted = 1
            return .first
        }
        guard frame.width == width, frame.height == previous.height,
              let match = OverlapSearch.match(previous, frame, expected: expectedShift)
        else { return .lost }
        if match.shift == 0 { return .unchanged }
        if match.shift < 0 { return .backward(shift: match.shift) }
        if offset + match.shift + frame.height > maxHeight { return .full }

        header = match.header
        footer = match.footer
        if !scrollerSeen, frame.matchWidth < width {
            scrollerSeen = Self.bandMoved(previous, frame, shift: match.shift, rows: match.header..<(frame.height - match.footer - match.shift))
        }
        // The previous frame's rows above this pair's footer are content. (A footer
        // guessed smaller last time may already have written them.)
        let from = written - offset, to = previous.height - match.footer
        if to > from { write(previous, rows: from..<to) }
        last = frame
        offset += match.shift
        accepted += 1
        return .appended(shift: match.shift)
    }

    /// Rows `range` of the output so far, as 4-byte pixels — for the live preview.
    public func writtenPixels(_ range: Range<Int>) -> [UInt8] {
        let rowBytes = width * 4
        return Array(canvas[(range.lowerBound * rowBytes)..<(range.upperBound * rowBytes)])
    }

    /// Width of the finished image: the frames' width, less the scroller band once a
    /// scroller has shown up in it.
    public var outputWidth: Int { scrollerSeen ? (last?.matchWidth ?? width) : width }

    /// The finished image: everything written plus the whole rest of the last frame,
    /// footer included. `bitmapInfo` and `colorSpace` describe the frames' pixels.
    public func image(colorSpace: CGColorSpace, bitmapInfo: CGBitmapInfo) -> CGImage? {
        guard let last else { return nil }
        var pixels = canvas
        pixels.append(contentsOf: last.pixels[(pendingRows.lowerBound * last.bytesPerRow)...])
        let keep = outputWidth
        if keep < width {
            let rowBytes = width * 4, keptBytes = keep * 4
            var cropped = [UInt8](repeating: 0, count: keptBytes * height)
            for row in 0..<height {
                cropped.replaceSubrange((row * keptBytes)..<((row + 1) * keptBytes), with: pixels[(row * rowBytes)..<(row * rowBytes + keptBytes)])
            }
            pixels = cropped
        }
        return Self.image(pixels: pixels, width: keep, height: height, colorSpace: colorSpace, bitmapInfo: bitmapInfo)
    }

    /// Whether the band right of the matched columns changed between two frames on
    /// rows that show the same content: next's row i is previous's row i + shift.
    static func bandMoved(_ previous: ScrollFrame, _ next: ScrollFrame, shift: Int, rows: Range<Int>) -> Bool {
        guard !rows.isEmpty else { return false }
        var changedRows = 0
        for i in rows {
            let p = (i + shift) * previous.bytesPerRow, q = i * next.bytesPerRow
            var differing = 0
            for x in next.matchWidth..<next.width {
                for c in 0..<3 where abs(Int(next.pixels[q + x * 4 + c]) - Int(previous.pixels[p + x * 4 + c])) > ScrollFrame.noise {
                    differing += 1
                    break
                }
            }
            if differing > 1 { changedRows += 1 }
            if changedRows > 3 { return true }
        }
        return false
    }

    public static func image(
        pixels: [UInt8], width: Int, height: Int, colorSpace: CGColorSpace, bitmapInfo: CGBitmapInfo
    ) -> CGImage? {
        guard width > 0, height > 0, pixels.count >= width * height * 4,
              let provider = CGDataProvider(data: Data(pixels) as CFData)
        else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: bitmapInfo, provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private mutating func write(_ frame: ScrollFrame, rows: Range<Int>) {
        guard !rows.isEmpty else { return }
        if canvas.isEmpty { canvas.reserveCapacity(min(maxHeight, frame.height * 8) * frame.bytesPerRow) }
        canvas.append(contentsOf: frame.pixels[(rows.lowerBound * frame.bytesPerRow)..<(rows.upperBound * frame.bytesPerRow)])
        written += rows.count
    }
}
