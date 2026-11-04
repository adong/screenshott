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

    /// Where the coordinates-and-color tag goes: just beside the cursor, above it when
    /// the loupe is below and below it when the loupe is above, so neither covers the
    /// other. Near the screen edges it tries the other sides of the cursor, then the far
    /// side of the loupe, and takes the first spot that fits on screen without touching
    /// the loupe. `loupe` is nil when the magnifier is off. View points, bottom-left origin.
    public static func tagFrame(
        size: CGSize, cursor: CGPoint, in bounds: CGSize, loupe: CGRect?, gap: CGFloat = 12
    ) -> CGRect {
        let loupeBelow = loupe.map { $0.midY < cursor.y } ?? true
        let loupeRight = loupe.map { $0.midX > cursor.x } ?? true
        let right = cursor.x + gap, left = cursor.x - gap - size.width
        let above = cursor.y + gap, below = cursor.y - gap - size.height
        let away = loupeBelow ? above : below, toward = loupeBelow ? below : above
        var spots = [
            CGPoint(x: right, y: away), CGPoint(x: left, y: away),
            CGPoint(x: loupeRight ? left : right, y: cursor.y - size.height / 2),
            CGPoint(x: right, y: toward), CGPoint(x: left, y: toward),
        ]
        if let loupe {
            spots += [CGPoint(x: loupe.maxX + gap / 2, y: toward), CGPoint(x: loupe.minX - gap / 2 - size.width, y: toward)]
        }
        let screen = CGRect(origin: .zero, size: bounds)
        for spot in spots {
            let frame = CGRect(origin: spot, size: size)
            if screen.contains(frame), !(loupe?.intersects(frame) ?? false) { return frame }
        }
        return CGRect(
            x: clamp(spots[0].x, 0, max(bounds.width - size.width, 0)),
            y: clamp(spots[0].y, 0, max(bounds.height - size.height, 0)),
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
