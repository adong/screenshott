import CoreGraphics
import Testing
@testable import ScreenshottCore

/// A tall made-up page: rows of noise like lines of text, with blank rows between them
/// like line spacing, so rows are distinctive but blank space repeats — as on a real
/// page. Frames are windows onto it, with optional sticky rows on top and bottom.
private struct Page {
    let width: Int
    var rows: [[UInt8]]

    static let blank = [UInt8](repeating: 0xFF, count: 4)

    init(width: Int = 48, height: Int, seed: UInt64 = 1, blankFrom: Range<Int> = 0..<0) {
        self.width = width
        var random = SplitMix(seed: seed)
        rows = (0..<height).map { row in
            // Six blank rows after every fourteen of "text".
            if row % 20 >= 14 || blankFrom.contains(row) { return Self.blankRow(width) }
            return Self.noiseRow(width, &random)
        }
    }

    static func blankRow(_ width: Int) -> [UInt8] { Array([[UInt8]](repeating: blank, count: width).joined()) }

    static func noiseRow(_ width: Int, _ random: inout SplitMix) -> [UInt8] {
        (0..<width).flatMap { _ -> [UInt8] in
            let v = random.next()
            return [UInt8(truncatingIfNeeded: v), UInt8(truncatingIfNeeded: v >> 8), UInt8(truncatingIfNeeded: v >> 16), 0xFF]
        }
    }

    /// `height` rows: `header`, then the page from `offset`, then `footer`.
    func frame(at offset: Int, height: Int, header: [[UInt8]] = [], footer: [[UInt8]] = [], ignoring: Int = 0) -> ScrollFrame {
        let body = height - header.count - footer.count
        let all = header + rows[offset..<(offset + body)] + footer
        return ScrollFrame(width: width, height: height, pixels: Array(all.joined()), ignoringTrailingColumns: ignoring)
    }

    /// What a perfect stitch of frames ending at `lastOffset` looks like.
    func expected(through lastOffset: Int, height: Int, header: [[UInt8]] = [], footer: [[UInt8]] = []) -> [UInt8] {
        let body = height - header.count - footer.count
        return Array((header + rows[0..<(lastOffset + body)] + footer).joined())
    }
}

private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private func stitched(_ stitcher: ScrollStitcher) -> [UInt8] {
    var pixels = stitcher.writtenPixels(0..<stitcher.written)
    if let last = stitcher.last {
        pixels += last.pixels[(stitcher.pendingRows.lowerBound * last.bytesPerRow)...]
    }
    return pixels
}

private func stitch(_ frames: [ScrollFrame], maxHeight: Int = ScrollStitcher.defaultMaxHeight) -> (ScrollStitcher, [ScrollStitcher.Step]) {
    var stitcher = ScrollStitcher(maxHeight: maxHeight)
    let steps = frames.map { stitcher.add($0) }
    return (stitcher, steps)
}

// MARK: - Overlap search

@Test func findsHowFarTheContentMovedEitherWay() throws {
    let page = Page(height: 400)
    let a = page.frame(at: 100, height: 120)
    let down = try #require(OverlapSearch.match(a, page.frame(at: 137, height: 120)))
    #expect(down.shift == 37)
    let up = try #require(OverlapSearch.match(a, page.frame(at: 75, height: 120)))
    #expect(up.shift == -25)
}

@Test func aBlinkingCaretIsNotMovement() throws {
    let page = Page(height: 200)
    let a = page.frame(at: 10, height: 120)
    var pixels = a.pixels
    for byte in 0..<8 { pixels[50 * a.bytesPerRow + 20 * 4 + byte] = 0 }  // two pixels in row 50
    let b = ScrollFrame(width: a.width, height: a.height, pixels: pixels)
    let match = try #require(OverlapSearch.match(a, b))
    #expect(match.shift == 0)
}

@Test func aSpinnerInTheMiddleIsNotALostOverlap() throws {
    let page = Page(height: 200)
    let a = page.frame(at: 0, height: 120)
    var random = SplitMix(seed: 99)
    var pixels = a.pixels
    for row in 55..<70 {
        let noise = Page.noiseRow(a.width, &random)
        pixels.replaceSubrange((row * a.bytesPerRow)..<((row + 1) * a.bytesPerRow), with: noise)
    }
    let match = try #require(OverlapSearch.match(a, ScrollFrame(width: a.width, height: a.height, pixels: pixels)))
    #expect(match.shift == 0)
}

@Test func aJumpPastTheWholeFrameHasNoMatch() {
    let page = Page(height: 600)
    #expect(OverlapSearch.match(page.frame(at: 0, height: 100), page.frame(at: 300, height: 100)) == nil)
}

@Test func expectedShiftPicksAmongRepeatingRows() throws {
    // A page whose 20-row pattern repeats: moving 30 rows also lines up at 10, 50, 70.
    var page = Page(height: 20)
    page.rows = Array(Array(repeating: page.rows, count: 15).joined())
    let a = page.frame(at: 0, height: 100), b = page.frame(at: 30, height: 100)
    // Without a hint any of them fits; the one with the most overlap wins.
    #expect(try abs(#require(OverlapSearch.match(a, b)).shift) == 10)
    #expect(OverlapSearch.match(a, b, expected: 33)?.shift == 30)
    #expect(OverlapSearch.match(a, b, expected: 48)?.shift == 50)
}

@Test func aFewChangedRowsAreForgivenWhileScrolling() throws {
    let page = Page(height: 400)
    let a = page.frame(at: 50, height: 150)
    let b = page.frame(at: 90, height: 150)
    var random = SplitMix(seed: 7)
    var pixels = b.pixels
    for row in 20..<24 {  // an animated thing in the body
        pixels.replaceSubrange((row * b.bytesPerRow)..<((row + 1) * b.bytesPerRow), with: Page.noiseRow(b.width, &random))
    }
    let match = try #require(OverlapSearch.match(a, ScrollFrame(width: b.width, height: b.height, pixels: pixels)))
    #expect(match.shift == 40)
}

// MARK: - Stitching

@Test func framesStitchBackIntoThePage() {
    let page = Page(height: 900)
    let offsets = [0, 37, 80, 150, 151, 230, 300, 333]
    let (stitcher, steps) = stitch(offsets.map { page.frame(at: $0, height: 120) })
    #expect(steps.first == .first)
    #expect(steps.dropFirst().allSatisfy { if case .appended = $0 { true } else { false } })
    #expect(stitcher.height == 333 + 120)
    #expect(stitched(stitcher) == page.expected(through: 333, height: 120))
}

@Test func stickyHeaderAndFooterAppearOnce() {
    let page = Page(height: 900, seed: 3)
    var random = SplitMix(seed: 42)
    let header = (0..<16).map { _ in Page.noiseRow(page.width, &random) }
    let footer = (0..<12).map { _ in Page.noiseRow(page.width, &random) }
    let offsets = [0, 50, 100, 150, 200, 260]
    let (stitcher, _) = stitch(offsets.map { page.frame(at: $0, height: 140, header: header, footer: footer) })
    #expect(stitcher.header >= 16 && stitcher.footer >= 12)
    #expect(stitcher.height == 260 + 140)
    #expect(stitched(stitcher) == page.expected(through: 260, height: 140, header: header, footer: footer))
}

@Test func theFooterComesFromTheLastFrameEvenWithABlinkingCaret() {
    let page = Page(height: 900, seed: 5)
    let footer = (0..<20).map { _ in Page.blankRow(page.width) }
    var frames: [ScrollFrame] = []
    var lastFooter = footer
    for (index, offset) in [0, 60, 120, 180].enumerated() {
        var rows = footer
        // The caret in the message box is on in odd frames.
        if index % 2 == 1 {
            for row in 4..<16 { rows[row].replaceSubrange(40..<48, with: [0, 0, 0, 0xFF, 0, 0, 0, 0xFF]) }
        }
        lastFooter = rows
        frames.append(page.frame(at: offset, height: 140, footer: rows))
    }
    let (stitcher, _) = stitch(frames)
    #expect(stitched(stitcher) == page.expected(through: 180, height: 140, footer: lastFooter))
}

@Test func blankRowsTakenForAFooterAreNotLost() {
    // The first two frames both end in a long blank stretch, so they agree on 36 rows at
    // the bottom and the stitcher takes them for a footer; the next pair corrects it.
    let page = Page(height: 900, seed: 8, blankFrom: 120..<200)
    var stitcher = ScrollStitcher()
    var footers: [Int] = []
    for offset in [0, 20, 70, 120, 170] {
        _ = stitcher.add(page.frame(at: offset, height: 150))
        footers.append(stitcher.footer)
    }
    #expect(footers.max() == 36)
    #expect(stitched(stitcher) == page.expected(through: 170, height: 150))
}

@Test func theScrollerBandIsLeftOutOfMatching() {
    let page = Page(height: 900, seed: 11)
    var frames: [ScrollFrame] = []
    for (index, offset) in [0, 45, 90, 135].enumerated() {
        var frame = page.frame(at: offset, height: 120)
        // A scroller thumb in the last 4 columns, further down each frame.
        var pixels = frame.pixels
        for row in (index * 25)..<(index * 25 + 30) {
            for column in (frame.width - 4)..<frame.width {
                pixels.replaceSubrange((row * frame.bytesPerRow + column * 4)..<(row * frame.bytesPerRow + column * 4 + 4), with: [0x80, 0x80, 0x80, 0xFF])
            }
        }
        frame = ScrollFrame(width: frame.width, height: frame.height, pixels: pixels, ignoringTrailingColumns: 4)
        frames.append(frame)
    }
    let (stitcher, steps) = stitch(frames)
    #expect(steps == [.first, .appended(shift: 45), .appended(shift: 45), .appended(shift: 45)])
    #expect(stitcher.height == 135 + 120)
    // A thumb at every seam would look broken: the band is cut off instead.
    #expect(stitcher.scrollerSeen)
    let image = stitcher.image(
        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    )
    #expect(image?.width == page.width - 4)
}

@Test func aStillBandIsKept() {
    let page = Page(height: 900, seed: 37)
    let (stitcher, _) = stitch([0, 45, 90].map { page.frame(at: $0, height: 120, ignoring: 4) })
    #expect(!stitcher.scrollerSeen)
    #expect(stitcher.outputWidth == page.width)
}

@Test func aLostFrameIsSkippedAndTheNextOneStillFits() {
    let page = Page(height: 900, seed: 13)
    let frames = [0, 50, 400, 100, 140].map { page.frame(at: $0, height: 120) }
    let (stitcher, steps) = stitch(frames)
    #expect(steps[2] == .lost)
    #expect(steps[3] == .appended(shift: 50))
    #expect(stitched(stitcher) == page.expected(through: 140, height: 120))
}

@Test func scrollingBackUpAndStillFramesAddNothing() {
    let page = Page(height: 900, seed: 17)
    let frames = [100, 100, 60, 130].map { page.frame(at: $0, height: 120) }
    let (stitcher, steps) = stitch(frames)
    #expect(steps == [.first, .unchanged, .backward(shift: -40), .appended(shift: 30)])
    #expect(stitcher.height == 30 + 120)
}

@Test func stopsBeforePassingTheHeightCap() {
    let page = Page(height: 900, seed: 19)
    let (stitcher, steps) = stitch(stride(from: 0, through: 400, by: 50).map { page.frame(at: $0, height: 120) }, maxHeight: 300)
    #expect(steps.contains(.full))
    #expect(stitcher.height <= 300)
    #expect(stitcher.height == 150 + 120)
}

@Test func theFinishedImageHasThePagesPixels() throws {
    let page = Page(width: 40, height: 500, seed: 23)
    var stitcher = ScrollStitcher()
    for offset in [0, 70, 140] {
        let pixels = page.frame(at: offset, height: 100).pixels
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let image = try #require(ScrollStitcher.image(pixels: pixels, width: 40, height: 100, colorSpace: space, bitmapInfo: info))
        _ = stitcher.add(try #require(ScrollFrame(image: image)))
    }
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let image = try #require(stitcher.image(
        colorSpace: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    ))
    #expect(image.width == 40 && image.height == 240)
    #expect(try #require(ScrollFrame(image: image)).pixels == page.expected(through: 140, height: 100))
}

/// `frame` with a quarter of its non-blank pixels one level lighter or darker — what an
/// app's text redraw does after scrolling.
private func redrawn(_ frame: ScrollFrame, seed: UInt64) -> ScrollFrame {
    var random = SplitMix(seed: seed)
    var pixels = frame.pixels
    for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i] != 0xFF && random.next() % 4 == 0 {
        for c in 0..<3 {
            let v = pixels[i + c]
            pixels[i + c] = v == 0 ? 1 : v == 0xFF ? 0xFE : random.next() % 2 == 0 ? v + 1 : v - 1
        }
    }
    return ScrollFrame(width: frame.width, height: frame.height, pixels: pixels)
}

@Test func redrawNoiseStillLinesUp() {
    let page = Page(height: 900, seed: 29)
    let frames = [0, 60, 130, 200].enumerated().map { redrawn(page.frame(at: $1, height: 120), seed: UInt64($0)) }
    let (stitcher, steps) = stitch(frames)
    #expect(steps == [.first, .appended(shift: 60), .appended(shift: 70), .appended(shift: 70)])
    #expect(stitcher.height == 200 + 120)
}

@Test func redrawNoiseAloneIsNotMovement() {
    let page = Page(height: 300, seed: 31)
    let a = page.frame(at: 40, height: 120)
    #expect(OverlapSearch.match(a, redrawn(a, seed: 9))?.shift == 0)
}
