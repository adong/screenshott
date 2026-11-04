import CoreGraphics

/// One frame of a scrolling capture: the selected region's pixels, 4 bytes each, top row
/// first, reduced to what the stitcher compares rows by. The channel order is whatever
/// the capture delivered (BGRA from ScreenCaptureKit); nothing here tells the colour
/// channels apart, and whoever turns pixels back into a CGImage says how to label them.
///
/// Rows that show the same content are not always the same bytes: apps redraw text
/// after scrolling, and the antialiasing can come out a level lighter or darker (seen
/// 2026-11-04: a quarter of the text rows off by 1 after a 300 px scroll). So rows are
/// compared by a hash when that agrees, and otherwise by the sums of a few column bands,
/// which such noise barely moves and different content moves a lot.
public struct ScrollFrame: Sendable {
    public let width: Int
    public let height: Int
    /// `width * 4` bytes per row, no padding.
    public let pixels: [UInt8]
    /// Rows are compared on the columns left of this. The rest is where an overlay
    /// scroller appears and moves while scrolling, which would make every row it
    /// crosses look changed.
    public let matchWidth: Int
    /// One hash per row, over the matched columns.
    let rowHashes: [UInt64]
    /// Rows whose matched columns are all one colour. Blank space matches at any
    /// shift, so it says nothing about how far the content moved.
    let uniformRows: [Bool]
    /// `bands` sums per row: the colour bytes of each band of matched columns, added up.
    let bandSums: [Int32]
    let bands: Int
    /// How far two band sums may differ for the same content: every pixel in the band
    /// one level off in every channel.
    let bandTolerance: Int32

    /// A channel step at most this big is redraw noise, not a change.
    static let noise = 8

    public var bytesPerRow: Int { width * 4 }

    /// `pixels` holds `height` rows of `bytesPerRow` bytes; the first `width * 4` of
    /// each are kept. `ignoringTrailingColumns` is the scroller band, left out of
    /// matching but kept in the pixels.
    public init(width: Int, height: Int, bytesPerRow: Int, pixels: UnsafeRawBufferPointer, ignoringTrailingColumns: Int = 0) {
        precondition(width > 0 && height > 0 && bytesPerRow >= width * 4 && pixels.count >= bytesPerRow * height)
        self.width = width
        self.height = height
        let rowBytes = width * 4
        if bytesPerRow == rowBytes {
            self.pixels = Array(pixels[0..<rowBytes * height])
        } else {
            var packed = [UInt8](repeating: 0, count: rowBytes * height)
            packed.withUnsafeMutableBytes { out in
                for row in 0..<height {
                    out.baseAddress!.advanced(by: row * rowBytes)
                        .copyMemory(from: pixels.baseAddress!.advanced(by: row * bytesPerRow), byteCount: rowBytes)
                }
            }
            self.pixels = packed
        }
        // Keep at least half the width, so a narrow selection still has columns to match.
        let matchWidth = max(width - max(ignoringTrailingColumns, 0), (width + 1) / 2)
        self.matchWidth = matchWidth
        bands = min(32, matchWidth)
        let bandWidth = (matchWidth + bands - 1) / bands
        bandTolerance = Int32(3 * bandWidth + 8)
        (rowHashes, uniformRows, bandSums) = Self.summarize(
            self.pixels, width: width, height: height, matchWidth: matchWidth, bands: bands, bandWidth: bandWidth
        )
    }

    public init(width: Int, height: Int, pixels: [UInt8], ignoringTrailingColumns: Int = 0) {
        self = pixels.withUnsafeBytes {
            ScrollFrame(width: width, height: height, bytesPerRow: width * 4, pixels: $0, ignoringTrailingColumns: ignoringTrailingColumns)
        }
    }

    /// Draws `image` into 4-byte pixels in its own colour space, so nothing is converted.
    public init?(image: CGImage, ignoringTrailingColumns: Int = 0) {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.init(width: width, height: height, pixels: pixels, ignoringTrailingColumns: ignoringTrailingColumns)
    }

    /// True when row `a` here and row `b` of `other` show the same content: equal
    /// hashes, or band sums within redraw noise. For the shift search, which makes
    /// many of these comparisons; most fail on the first band.
    func row(_ a: Int, matches b: Int, of other: ScrollFrame) -> Bool {
        if rowHashes[a] == other.rowHashes[b] { return true }
        guard bands == other.bands else { return false }
        return bandSums.withUnsafeBufferPointer { mine in
            other.bandSums.withUnsafeBufferPointer { theirs in
                let p = a * bands, q = b * bands
                for k in 0..<bands where abs(mine[p + k] - theirs[q + k]) > bandTolerance { return false }
                return true
            }
        }
    }

    /// True when row `a` here and row `b` of `other` differ in at most `tolerance`
    /// matched pixels, not counting redraw noise — a blinking caret or a spinner is not
    /// a different row.
    func row(_ a: Int, nearlyEquals b: Int, of other: ScrollFrame, tolerance: Int) -> Bool {
        if rowHashes[a] == other.rowHashes[b] { return true }
        var differing = 0
        return pixels.withUnsafeBytes { mine in
            other.pixels.withUnsafeBytes { theirs in
                let p = mine.baseAddress!.advanced(by: a * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                let q = theirs.baseAddress!.advanced(by: b * other.bytesPerRow).assumingMemoryBound(to: UInt8.self)
                for x in 0..<min(matchWidth, other.matchWidth) {
                    let i = x * 4
                    if abs(Int(p[i]) - Int(q[i])) > Self.noise || abs(Int(p[i + 1]) - Int(q[i + 1])) > Self.noise
                        || abs(Int(p[i + 2]) - Int(q[i + 2])) > Self.noise {
                        differing += 1
                        if differing > tolerance { return false }
                    }
                }
                return true
            }
        }
    }

    private static func summarize(
        _ pixels: [UInt8], width: Int, height: Int, matchWidth: Int, bands: Int, bandWidth: Int
    ) -> ([UInt64], [Bool], [Int32]) {
        var hashes = [UInt64](repeating: 0, count: height)
        var uniform = [Bool](repeating: false, count: height)
        var sums = [Int32](repeating: 0, count: height * bands)
        pixels.withUnsafeBytes { buffer in
            sums.withUnsafeMutableBufferPointer { sums in
                for row in 0..<height {
                    let base = buffer.baseAddress!.advanced(by: row * width * 4)
                    let first = base.loadUnaligned(as: UInt32.self)
                    var same = true
                    var h: UInt64 = 0xCBF2_9CE4_8422_2325
                    for x in 0..<matchWidth {
                        let pixel = base.loadUnaligned(fromByteOffset: x * 4, as: UInt32.self)
                        same = same && pixel == first
                        h = (h ^ UInt64(pixel)) &* 0x9E37_79B9_7F4A_7C15
                        h ^= h >> 29
                        // Bytes 0–2 are colour in both BGRA and RGBA order; byte 3 is alpha.
                        sums[row * bands + x / bandWidth] += Int32(pixel & 0xFF) + Int32((pixel >> 8) & 0xFF)
                            + Int32((pixel >> 16) & 0xFF)
                    }
                    hashes[row] = h
                    uniform[row] = same
                }
            }
        }
        return (hashes, uniform, sums)
    }
}
