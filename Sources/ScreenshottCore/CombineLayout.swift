/// How the captures of a combined canvas are placed (decisions 3 and 3a): in one row
/// or column, a uniform gap apart, lined up along one side or centered. Automatic
/// only; dragging captures around freely is P1.
public struct CombineLayout: Codable, Hashable, Sendable {
    public enum Direction: String, Codable, Sendable, CaseIterable {
        /// One above the other.
        case vertical
        /// Side by side.
        case horizontal
    }

    /// Across the direction: left / center / right for a column, top / center /
    /// bottom for a row.
    public enum Alignment: String, Codable, Sendable, CaseIterable {
        case leading, center, trailing
    }

    public var direction: Direction
    public var alignment: Alignment
    /// The gap between neighbors, in canvas pixels.
    public var spacing: Int

    public init(direction: Direction = .vertical, alignment: Alignment = .leading, spacing: Int) {
        self.direction = direction
        self.alignment = alignment
        self.spacing = spacing
    }

    /// The default for a canvas at `scale`: a column, left-aligned, 16 points apart.
    public static func standard(scale: Double) -> CombineLayout {
        CombineLayout(spacing: Int((16 * scale).rounded()))
    }

    /// Moves each capture to its place.
    func place(_ images: inout [CanvasImage]) {
        for (index, origin) in origins(for: images.map(\.crop.size)).enumerated() { images[index].origin = origin }
    }

    /// Top-left corner of each of `sizes`, in order, starting at (0, 0).
    public func origins(for sizes: [PixelSize]) -> [PixelPoint] {
        let across = sizes.map { direction == .vertical ? $0.width : $0.height }
        let widest = across.max() ?? 0
        var along = 0
        return sizes.indices.map { index in
            let size = sizes[index]
            let offset = switch alignment {
            case .leading: 0
            case .center: (widest - across[index]) / 2
            case .trailing: widest - across[index]
            }
            defer { along += (direction == .vertical ? size.height : size.width) + max(spacing, 0) }
            return direction == .vertical ? PixelPoint(x: offset, y: along) : PixelPoint(x: along, y: offset)
        }
    }
}
