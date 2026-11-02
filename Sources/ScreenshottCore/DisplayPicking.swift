import CoreGraphics

public enum DisplayPicking {
    /// Index of the display frame that contains `point`. Frames and point must share one
    /// coordinate space — pass `NSScreen.frame`s with `NSEvent.mouseLocation` (both
    /// Cocoa, bottom-left origin), never `SCDisplay.frame` (CoreGraphics, top-left).
    ///
    /// `CGRect.contains` is half-open, so a cursor parked on a screen's top or right
    /// edge matches nothing; the second pass treats edges as inside.
    public static func index(containing point: CGPoint, in frames: [CGRect]) -> Int? {
        if let i = frames.firstIndex(where: { $0.contains(point) }) { return i }
        return frames.firstIndex { frame in
            point.x >= frame.minX && point.x <= frame.maxX
                && point.y >= frame.minY && point.y <= frame.maxY
        }
    }
}
