/// The area selection on one display's overlay, in that display's pixels. Pure state,
/// so the mouse and keyboard rules are testable without a window.
///
/// A drag that starts outside the selection draws a new one; inside moves it; on an
/// edge or corner resizes it. Nothing changes until the pointer leaves `clickSlop`,
/// so a press that stays put is a click and the caller decides what a click means.
public struct SelectionModel: Sendable {
    public enum Handle: Sendable, Equatable, CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    public enum Hit: Sendable, Equatable {
        case handle(Handle)
        case inside
        case outside
    }

    private enum Drag: Sendable {
        case creating(anchor: PixelPoint)
        case moving(from: PixelRect)
        case resizing(Handle, from: PixelRect)
    }

    public let bounds: PixelSize
    public let clickSlop: Int
    public var selection: PixelRect?

    private var drag: Drag?
    private var start = PixelPoint(x: 0, y: 0)
    private var leftSlop = false

    public init(bounds: PixelSize, clickSlop: Int) {
        self.bounds = bounds
        self.clickSlop = clickSlop
    }

    /// True while a drag that started inside the selection is carrying it along.
    public var isMoving: Bool {
        if case .moving = drag, leftSlop { return true }
        return false
    }

    /// Which part of the selection `p` lands on. Edges catch the pointer within
    /// `tolerance` pixels on either side; when a selection is thinner than that, the
    /// nearer edge wins.
    public func hit(_ p: PixelPoint, tolerance: Int) -> Hit {
        guard let r = selection,
              p.x >= r.minX - tolerance, p.x <= r.maxX + tolerance,
              p.y >= r.minY - tolerance, p.y <= r.maxY + tolerance
        else { return .outside }

        let horizontal = nearer(p.x, low: r.minX, high: r.maxX, tolerance: tolerance)
        let vertical = nearer(p.y, low: r.minY, high: r.maxY, tolerance: tolerance)
        switch (vertical, horizontal) {
        case (.low?, .low?): return .handle(.topLeft)
        case (.low?, .high?): return .handle(.topRight)
        case (.high?, .low?): return .handle(.bottomLeft)
        case (.high?, .high?): return .handle(.bottomRight)
        case (.low?, nil): return .handle(.top)
        case (.high?, nil): return .handle(.bottom)
        case (nil, .low?): return .handle(.left)
        case (nil, .high?): return .handle(.right)
        case (nil, nil):
            let inside = p.x >= r.minX && p.x <= r.maxX && p.y >= r.minY && p.y <= r.maxY
            return inside ? .inside : .outside
        }
    }

    /// Starts a press at grid point `p`. Returns what the press landed on.
    @discardableResult
    public mutating func begin(at p: PixelPoint, tolerance: Int) -> Hit {
        let hit = hit(p, tolerance: tolerance)
        start = p
        leftSlop = false
        switch (hit, selection) {
        case (.handle(let handle), let r?): drag = .resizing(handle, from: r)
        case (.inside, let r?): drag = .moving(from: r)
        default: drag = .creating(anchor: p)
        }
        return hit
    }

    public mutating func drag(to p: PixelPoint) {
        guard let drag else { return }
        if !leftSlop {
            guard max(abs(p.x - start.x), abs(p.y - start.y)) > clickSlop else { return }
            leftSlop = true
        }
        switch drag {
        case .creating(let anchor):
            selection = PixelRect(corner: anchor, p)
        case .moving(let from):
            selection = moved(from, dx: p.x - start.x, dy: p.y - start.y)
        case .resizing(let handle, let from):
            selection = resized(from, handle: handle, to: p)
        }
    }

    /// Ends the press. Returns true when the pointer never left the slop — a click.
    public mutating func end() -> Bool {
        defer { drag = nil }
        return drag != nil && !leftSlop
    }

    /// Arrow keys: moves the selection, stopping at the image edges.
    public mutating func nudge(dx: Int, dy: Int) {
        guard let r = selection else { return }
        selection = moved(r, dx: dx, dy: dy)
    }

    /// ⌥ + arrow keys: moves the right and bottom edges. Never below one pixel.
    public mutating func resize(dx: Int, dy: Int) {
        guard var r = selection else { return }
        r.width = clamp(r.width + dx, 1, bounds.width - r.minX)
        r.height = clamp(r.height + dy, 1, bounds.height - r.minY)
        selection = r
    }

    private func moved(_ r: PixelRect, dx: Int, dy: Int) -> PixelRect {
        PixelRect(
            x: clamp(r.minX + dx, 0, bounds.width - r.width),
            y: clamp(r.minY + dy, 0, bounds.height - r.height),
            width: r.width, height: r.height
        )
    }

    /// Drags one edge or corner to `p`. Dragging past the opposite edge flips the
    /// rectangle instead of inverting it.
    private func resized(_ r: PixelRect, handle: Handle, to p: PixelPoint) -> PixelRect {
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
        return PixelRect(corner: PixelPoint(x: x0, y: y0), PixelPoint(x: x1, y: y1))
    }

    private enum Side { case low, high }

    private func nearer(_ v: Int, low: Int, high: Int, tolerance: Int) -> Side? {
        let toLow = abs(v - low), toHigh = abs(v - high)
        switch (toLow <= tolerance, toHigh <= tolerance) {
        case (true, true): return toLow <= toHigh ? .low : .high
        case (true, false): return .low
        case (false, true): return .high
        case (false, false): return nil
        }
    }
}
