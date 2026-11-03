import CoreGraphics

public enum MagnifierLayout {
    /// Source pixels per side. Odd, so one pixel sits exactly in the middle.
    public static let side = 15

    /// The pixels the loupe shows around `center`. At image edges the square slides
    /// inward instead of shrinking, so the zoom stays constant; `marker` is where
    /// `center` falls inside it.
    public static func source(
        around center: PixelPoint, side: Int = side, in bounds: PixelSize
    ) -> (rect: PixelRect, marker: PixelPoint) {
        let w = min(side, bounds.width), h = min(side, bounds.height)
        let x = clamp(center.x - w / 2, 0, bounds.width - w)
        let y = clamp(center.y - h / 2, 0, bounds.height - h)
        return (PixelRect(x: x, y: y, width: w, height: h), PixelPoint(x: center.x - x, y: center.y - y))
    }

    /// Where to draw the loupe: below and to the right of the cursor, switching sides
    /// near the screen's right and bottom edges. View points, bottom-left origin.
    public static func frame(size: CGSize, cursor: CGPoint, in bounds: CGSize, offset: CGFloat = 24) -> CGRect {
        var x = cursor.x + offset
        if x + size.width > bounds.width { x = cursor.x - offset - size.width }
        var y = cursor.y - offset - size.height
        if y < 0 { y = cursor.y + offset }
        return CGRect(
            x: clamp(x, 0, max(bounds.width - size.width, 0)),
            y: clamp(y, 0, max(bounds.height - size.height, 0)),
            width: size.width, height: size.height
        )
    }
}

public enum ThumbnailLayout {
    public static let maxSize = CGSize(width: 240, height: 160)
    /// Small enough for a 1-pixel capture, big enough to grab and drag.
    public static let minSide: CGFloat = 56

    /// Point size of the thumbnail for a capture `pixels` big at `scale`: the image
    /// aspect-fit into `maxSize`, never enlarged, each side at least `minSide` (the
    /// image is drawn aspect-fit inside, so a sliver capture gets a padded tile).
    public static func size(for pixels: PixelSize, scale: CGFloat) -> CGSize {
        let w = CGFloat(pixels.width) / scale, h = CGFloat(pixels.height) / scale
        guard w > 0, h > 0 else { return CGSize(width: minSide, height: minSide) }
        let fit = min(maxSize.width / w, maxSize.height / h, 1)
        return CGSize(width: max((w * fit).rounded(), minSide), height: max((h * fit).rounded(), minSide))
    }

    /// Frames for a stack of thumbnails in one screen's `visibleFrame` (Cocoa points):
    /// right-aligned at the bottom-right corner, `sizes[0]` at the bottom, each next one
    /// above the last.
    public static func frames(
        sizes: [CGSize], in visibleFrame: CGRect, margin: CGFloat = 16, spacing: CGFloat = 12
    ) -> [CGRect] {
        var y = visibleFrame.minY + margin
        return sizes.map { size in
            defer { y += size.height + spacing }
            return CGRect(x: visibleFrame.maxX - margin - size.width, y: y, width: size.width, height: size.height)
        }
    }
}
