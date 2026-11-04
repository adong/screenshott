import CoreGraphics

// Pixel types live apart from Cocoa points on purpose. Points have a bottom-left origin
// and fractional values; a captured image has whole pixels and a top-left origin.
// Mixing the two (and their two y directions) is the bug these types exist to stop.

/// A pixel in a captured image: top-left origin, physical pixels (CGImage's own space).
public struct PixelPoint: Hashable, Sendable, Codable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

public struct PixelSize: Hashable, Sendable, Codable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// A rectangle of whole pixels in a captured image, top-left origin.
public struct PixelRect: Hashable, Sendable, Codable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// The rectangle spanned by two corners, given in either order.
    public init(corner a: PixelPoint, _ b: PixelPoint) {
        self.init(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    public var minX: Int { x }
    public var minY: Int { y }
    public var maxX: Int { x + width }
    public var maxY: Int { y + height }
    public var isEmpty: Bool { width <= 0 || height <= 0 }
    public var size: PixelSize { PixelSize(width: width, height: height) }

    /// For `CGImage.cropping(to:)`, which also counts from the top-left.
    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    public func contains(_ p: PixelPoint) -> Bool {
        p.x >= minX && p.x < maxX && p.y >= minY && p.y < maxY
    }

    public func offsetBy(dx: Int, dy: Int) -> PixelRect {
        PixelRect(x: x + dx, y: y + dy, width: width, height: height)
    }

    /// The part inside an image of `size`, or nil when nothing is left.
    public func clamped(to size: PixelSize) -> PixelRect? {
        let x0 = max(minX, 0), y0 = max(minY, 0)
        let x1 = min(maxX, size.width), y1 = min(maxY, size.height)
        guard x1 > x0, y1 > y0 else { return nil }
        return PixelRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}

/// Maps between one overlay view and its display's frozen image. The view is a plain
/// (non-flipped) NSView covering the whole screen, so its points have a bottom-left
/// origin; the image's pixels have a top-left origin.
public struct OverlayGeometry: Sendable {
    public let pointSize: CGSize
    public let pixelSize: PixelSize

    public init(pointSize: CGSize, pixelSize: PixelSize) {
        self.pointSize = pointSize
        self.pixelSize = pixelSize
    }

    /// Pixels per point — 2 on Retina. Read off the image rather than taken from
    /// `NSScreen.backingScaleFactor`, so the two can never disagree.
    public var scale: CGFloat { CGFloat(pixelSize.width) / pointSize.width }

    /// The pixel under a view point — for hit tests and the magnifier.
    public func pixel(at p: CGPoint) -> PixelPoint {
        PixelPoint(
            x: clamp(Int((p.x * scale).rounded(.down)), 0, pixelSize.width - 1),
            y: clamp(Int(((pointSize.height - p.y) * scale).rounded(.down)), 0, pixelSize.height - 1)
        )
    }

    /// The pixel grid line nearest a view point. Selection edges sit between pixels,
    /// so a drag from one edge to another covers whole pixels.
    public func edge(at p: CGPoint) -> PixelPoint {
        PixelPoint(
            x: clamp(Int((p.x * scale).rounded()), 0, pixelSize.width),
            y: clamp(Int(((pointSize.height - p.y) * scale).rounded()), 0, pixelSize.height)
        )
    }

    /// Where a pixel rectangle sits in the view.
    public func viewRect(for r: PixelRect) -> CGRect {
        CGRect(
            x: CGFloat(r.minX) / scale,
            y: pointSize.height - CGFloat(r.maxY) / scale,
            width: CGFloat(r.width) / scale,
            height: CGFloat(r.height) / scale
        )
    }

    /// A window's rectangle in this display's pixels, cut to the display. Both
    /// arguments are global CoreGraphics points (top-left origin of the main display):
    /// what `CGWindowListCopyWindowInfo` and `CGDisplayBounds` report.
    public func pixelRect(forGlobal window: CGRect, displayBounds: CGRect) -> PixelRect? {
        let local = window.offsetBy(dx: -displayBounds.minX, dy: -displayBounds.minY)
        let x0 = Int((local.minX * scale).rounded()), y0 = Int((local.minY * scale).rounded())
        let x1 = Int((local.maxX * scale).rounded()), y1 = Int((local.maxY * scale).rounded())
        return PixelRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0).clamped(to: pixelSize)
    }
}

public enum GlobalCoordinates {
    /// Cocoa global (bottom-left of the main screen, y up) → CoreGraphics global
    /// (top-left of the main screen, y down), e.g. for `CGWarpMouseCursorPosition`.
    public static func cgPoint(fromCocoa p: CGPoint, mainScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: mainScreenHeight - p.y)
    }
}

func clamp<T: Comparable>(_ value: T, _ low: T, _ high: T) -> T {
    min(max(value, low), high)
}
