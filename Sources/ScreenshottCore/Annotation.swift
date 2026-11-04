import CoreGraphics
import Foundation

/// An object drawn over the captures. One flat type for every kind keeps the JSON
/// simple and lets every kind share the same drag code; fields a kind doesn't use
/// keep their defaults. Rectangle, ellipse and triangle are outline shapes that fill
/// the rectangle spanned by `start` and `end`.
public struct Annotation: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case arrow, rectangle, ellipse, triangle, text, pixelate

        /// The outline shapes: they fill `rect`, reshape by its eight handles and only
        /// catch presses on their line until selected.
        public var isShape: Bool { [.rectangle, .ellipse, .triangle].contains(self) }

        /// Height over width when ⇧ constrains the shape: a square, a circle, or an
        /// equilateral triangle.
        var constrainedAspect: Double { self == .triangle ? 3.squareRoot() / 2 : 1 }
    }

    /// How a pixelate hides what is under it. Mosaicked text can be recovered by tools
    /// like Depix, so `solid` paints it out instead (decision 7a).
    public enum Cover: String, Codable, Sendable, CaseIterable {
        case mosaic, solid
    }

    public var id: UUID
    public var kind: Kind
    /// Arrow: the tail. Shapes and pixelate: a corner. Text: the top-left corner.
    public var start: CGPoint
    /// Arrow: the head. Shapes and pixelate: the opposite corner. Text: unused.
    public var end: CGPoint
    public var color: RGBAColor
    /// Line width (arrow, shapes) or font size (text), in canvas pixels.
    public var size: Double
    public var text: String
    public var cover: Cover
    /// The capture it was drawn on. It moves with that capture when a crop or the
    /// layout moves it.
    public var anchor: UUID?

    public init(
        id: UUID = UUID(), kind: Kind, start: CGPoint, end: CGPoint, color: RGBAColor = RGBAColor.palette[0],
        size: Double, text: String = "", cover: Cover = .mosaic, anchor: UUID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.color = color
        self.size = size
        self.text = text
        self.cover = cover
        self.anchor = anchor
    }

    /// The rectangle spanned by `start` and `end`.
    public var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    /// Everything the annotation paints, for redraws and selection outlines.
    public var bounds: CGRect {
        switch kind {
        case .arrow: ArrowShape.path(from: start, to: end, width: size).boundingBoxOfPath
        // The triangle's corners are drawn round, so its line stays inside this too.
        case .rectangle, .ellipse, .triangle: rect.insetBy(dx: -size / 2, dy: -size / 2)
        case .pixelate: rect
        case .text: CGRect(origin: start, size: TextLayout.size(of: text, fontSize: size))
        }
    }

    /// Too small to keep — a click that never became a drag.
    public var isNegligible: Bool {
        switch kind {
        case .arrow: hypot(end.x - start.x, end.y - start.y) < 4
        case .rectangle, .ellipse, .triangle, .pixelate: rect.width < 3 || rect.height < 3
        case .text: text.allSatisfy(\.isWhitespace)
        }
    }

    /// A triangle's corners: the apex at the middle of the top edge, then the bottom
    /// right and bottom left corners (canvas y grows downward).
    public var trianglePoints: [CGPoint] {
        let r = rect
        return [CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
    }

    // MARK: - Hit-testing

    /// What a press grabs.
    public enum Part: Hashable, Sendable {
        case body
        /// An arrow's tail or head.
        case start, end
        /// A shape's or pixelate's corner or edge.
        case handle(SelectionModel.Handle)
    }

    /// The grab points a selected annotation shows.
    public var handles: [(Part, CGPoint)] {
        switch kind {
        case .arrow:
            return [(.start, start), (.end, end)]
        case .rectangle, .ellipse, .triangle, .pixelate:
            let r = rect
            return SelectionModel.Handle.allCases.map { handle in
                let x: CGFloat = switch handle {
                case .topLeft, .left, .bottomLeft: r.minX
                case .top, .bottom: r.midX
                case .topRight, .right, .bottomRight: r.maxX
                }
                let y: CGFloat = switch handle {
                case .topLeft, .top, .topRight: r.minY
                case .left, .right: r.midY
                case .bottomLeft, .bottom, .bottomRight: r.maxY
                }
                return (.handle(handle), CGPoint(x: x, y: y))
            }
        case .text:
            return []
        }
    }

    /// Whether `p` lands on the annotation, within `tolerance`. An outline shape only
    /// catches presses on its line, so you can still draw inside it — unless it is
    /// selected, when its inside grabs it too.
    public func contains(_ p: CGPoint, tolerance: Double, selected: Bool) -> Bool {
        switch kind {
        case .arrow:
            return distance(from: p, toSegment: start, end) <= tolerance + size / 2
                || ArrowShape.path(from: start, to: end, width: size).contains(p)
        case .rectangle:
            let reach = tolerance + size / 2
            guard rect.insetBy(dx: -reach, dy: -reach).contains(p) else { return false }
            let inner = rect.insetBy(dx: reach, dy: reach)
            return selected || inner.isNull || !inner.contains(p)
        case .ellipse:
            let reach = tolerance + size / 2
            let r = rect
            guard r.insetBy(dx: -reach, dy: -reach).contains(p) else { return false }
            let a = r.width / 2, b = r.height / 2
            guard a > 0, b > 0 else { return true }
            let dx = p.x - r.midX, dy = p.y - r.midY
            // 1 on the outline, less inside. Along the ray from the center, the outline
            // is |p − center| / k away from the center.
            let k = hypot(dx / a, dy / b)
            if selected, k <= 1 { return true }
            guard k > 0 else { return min(a, b) <= reach }
            return hypot(dx, dy) * abs(k - 1) / k <= reach
        case .triangle:
            let reach = tolerance + size / 2
            let corners = trianglePoints
            let onLine = (0..<3).contains { distance(from: p, toSegment: corners[$0], corners[($0 + 1) % 3]) <= reach }
            guard !onLine else { return true }
            guard selected else { return false }
            let path = CGMutablePath()
            path.addLines(between: corners)
            path.closeSubpath()
            return path.contains(p)
        case .pixelate, .text:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
        }
    }

    // MARK: - Editing

    public func moved(dx: Double, dy: Double) -> Annotation {
        var moved = self
        moved.start = CGPoint(x: start.x + dx, y: start.y + dy)
        moved.end = CGPoint(x: end.x + dx, y: end.y + dy)
        return moved
    }

    /// With `part` dragged to `p` (the body moves through `moved`). `constrained` (⇧)
    /// snaps arrows to 45° steps, makes rectangles square, ellipses circles and
    /// triangles equilateral.
    public func dragging(_ part: Part, to p: CGPoint, constrained: Bool) -> Annotation {
        var edited = self
        switch part {
        case .body:
            break
        case .start:
            edited.start = constrained ? constrain(p, from: end) : p
        case .end:
            edited.end = constrained ? constrain(p, from: start) : p
        case .handle(let handle):
            let r = rect
            var x0 = r.minX, y0 = r.minY, x1 = r.maxX, y1 = r.maxY
            switch handle {
            case .left, .topLeft, .bottomLeft: x0 = p.x
            case .right, .topRight, .bottomRight: x1 = p.x
            case .top, .bottom: break
            }
            switch handle {
            case .top, .topLeft, .topRight: y0 = p.y
            case .bottom, .bottomLeft, .bottomRight: y1 = p.y
            case .left, .right: break
            }
            // Keep start the top-left and end the bottom-right, flipping past an edge.
            edited.start = CGPoint(x: min(x0, x1), y: min(y0, y1))
            edited.end = CGPoint(x: max(x0, x1), y: max(y0, y1))
            if constrained, [.topLeft, .topRight, .bottomLeft, .bottomRight].contains(handle) {
                // Square off from the corner opposite the one being dragged.
                let anchor = CGPoint(
                    x: [.topLeft, .bottomLeft].contains(handle) ? r.maxX : r.minX,
                    y: [.topLeft, .topRight].contains(handle) ? r.maxY : r.minY
                )
                let corner = Self.proportioned(p, from: anchor, aspect: kind.constrainedAspect)
                edited.start = CGPoint(x: min(anchor.x, corner.x), y: min(anchor.y, corner.y))
                edited.end = CGPoint(x: max(anchor.x, corner.x), y: max(anchor.y, corner.y))
            }
        }
        return edited
    }

    private func constrain(_ p: CGPoint, from fixed: CGPoint) -> CGPoint {
        switch kind {
        case .arrow:
            let dx = p.x - fixed.x, dy = p.y - fixed.y
            let length = hypot(dx, dy)
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            return CGPoint(x: fixed.x + length * cos(angle), y: fixed.y + length * sin(angle))
        case .rectangle, .ellipse, .triangle, .pixelate:
            return Self.proportioned(p, from: fixed, aspect: kind.constrainedAspect)
        case .text:
            return p
        }
    }

    /// The corner opposite `fixed` for a box of height / width `aspect` that reaches
    /// at least as far as `p` in both directions, on `p`'s side of `fixed`.
    private static func proportioned(_ p: CGPoint, from fixed: CGPoint, aspect: Double) -> CGPoint {
        let dx = p.x - fixed.x, dy = p.y - fixed.y
        let width = max(abs(dx), abs(dy) / aspect)
        let height = width * aspect
        return CGPoint(x: fixed.x + (dx < 0 ? -width : width), y: fixed.y + (dy < 0 ? -height : height))
    }
}

func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> Double {
    let dx = b.x - a.x, dy = b.y - a.y
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
    let t = clamp(((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared, 0, 1)
    return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
}

public enum ArrowShape {
    /// The arrow as one closed outline to fill: a shaft that widens from half of
    /// `width` at the tail to `width` at the head, and a head about 3½ widths long.
    /// A short arrow gets a shorter head so it never overshoots the tail.
    public static func path(from tail: CGPoint, to head: CGPoint, width: Double) -> CGPath {
        let path = CGMutablePath()
        let dx = head.x - tail.x, dy = head.y - tail.y
        let length = hypot(dx, dy)
        guard length > 0.5 else { return path }
        let (ux, uy) = (dx / length, dy / length)
        let (nx, ny) = (-uy, ux)
        let headLength = min(max(width * 3.5, 10), length)
        let headHalf = max(headLength * 0.55, width)
        let base = CGPoint(x: head.x - ux * headLength, y: head.y - uy * headLength)
        let shaft = width / 2, tailHalf = width / 4
        path.addLines(between: [
            CGPoint(x: tail.x + nx * tailHalf, y: tail.y + ny * tailHalf),
            CGPoint(x: base.x + nx * shaft, y: base.y + ny * shaft),
            CGPoint(x: base.x + nx * headHalf, y: base.y + ny * headHalf),
            head,
            CGPoint(x: base.x - nx * headHalf, y: base.y - ny * headHalf),
            CGPoint(x: base.x - nx * shaft, y: base.y - ny * shaft),
            CGPoint(x: tail.x - nx * tailHalf, y: tail.y - ny * tailHalf),
        ])
        path.closeSubpath()
        return path
    }
}
