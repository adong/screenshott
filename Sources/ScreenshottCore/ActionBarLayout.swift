import CoreGraphics

/// Where the overlay's action bar goes: just below the selection, right-aligned with
/// it; above when there is no room below; inside its bottom edge when the selection
/// fills the screen. View points, bottom-left origin.
public enum ActionBarLayout {
    public static func frame(size: CGSize, below hole: CGRect, in bounds: CGSize, gap: CGFloat = 8) -> CGRect {
        let x = min(max(hole.maxX - size.width, 0), max(bounds.width - size.width, 0))
        let y: CGFloat
        if hole.minY - gap - size.height >= 0 {
            y = hole.minY - gap - size.height
        } else if hole.maxY + gap + size.height <= bounds.height {
            y = hole.maxY + gap
        } else {
            y = max(hole.minY + gap, 0)
        }
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// Item frames left to right inside the bar, each `widths[i]` wide.
    public static func items(widths: [CGFloat], height: CGFloat, padding: CGFloat = 4, spacing: CGFloat = 2) -> [CGRect] {
        var x = padding
        return widths.map { width in
            defer { x += width + spacing }
            return CGRect(x: x, y: padding, width: width, height: height - 2 * padding)
        }
    }

    public static func width(of widths: [CGFloat], padding: CGFloat = 4, spacing: CGFloat = 2) -> CGFloat {
        widths.reduce(0, +) + spacing * CGFloat(max(widths.count - 1, 0)) + 2 * padding
    }
}
