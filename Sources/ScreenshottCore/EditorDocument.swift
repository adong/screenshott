import CoreGraphics
import Foundation

// The editor's object-layer document (decision 7): every capture is its own image
// object, and annotations are objects on top. Canvas coordinates are pixels with a
// top-left origin, like PixelRect — a 2x capture is twice as many canvas pixels as
// points. Pixels themselves never go into the document; ProjectStore keeps each
// capture's original PNG beside the JSON (decision 7a).

/// An sRGB color with 0...1 components, so annotation colors survive the project JSON.
public struct RGBAColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

    public var opaque: RGBAColor { RGBAColor(red: red, green: green, blue: blue) }

    public static let white = RGBAColor(red: 1, green: 1, blue: 1)
    public static let black = RGBAColor(red: 0, green: 0, blue: 0)

    /// The editor's swatches; the first is the default.
    public static let palette: [RGBAColor] = [
        RGBAColor(red: 0.96, green: 0.24, blue: 0.20),
        RGBAColor(red: 1.00, green: 0.76, blue: 0.05),
        RGBAColor(red: 0.20, green: 0.78, blue: 0.35),
        RGBAColor(red: 0.04, green: 0.52, blue: 1.00),
        .black,
        .white,
    ]
}

/// One capture on the canvas.
public struct CanvasImage: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// The whole capture; `crop` is the part that shows.
    public var pixelSize: PixelSize
    public var crop: PixelRect
    /// Where the crop's top-left corner sits on the canvas.
    public var origin: PixelPoint

    public init(id: UUID = UUID(), pixelSize: PixelSize, origin: PixelPoint = PixelPoint(x: 0, y: 0)) {
        self.id = id
        self.pixelSize = pixelSize
        crop = PixelRect(x: 0, y: 0, width: pixelSize.width, height: pixelSize.height)
        self.origin = origin
    }

    /// The crop's place on the canvas.
    public var frame: PixelRect { PixelRect(x: origin.x, y: origin.y, width: crop.width, height: crop.height) }

    /// Where the capture's own pixel (0, 0) lands on the canvas. Annotations drawn on
    /// this capture move by however much this moves, so they stay on the same pixels.
    public var offset: PixelPoint { PixelPoint(x: origin.x - crop.x, y: origin.y - crop.y) }
}

public struct EditorDocument: Codable, Hashable, Sendable {
    /// Bumped when an older build could no longer read what this one writes.
    public static let formatVersion = 1

    public var version = Self.formatVersion
    /// Pixels per point of the captures: the exported PNG's DPI is 72 × this, and a
    /// "4 pt" line is 4 × this canvas pixels wide.
    public var scale: Double
    public var images: [CanvasImage]
    /// Drawn in order, so later ones are on top.
    public var annotations: [Annotation] = []
    /// Fills whatever part of the canvas no capture covers.
    public var background = RGBAColor.white
    /// Where combined captures go (M4). Change it through `setLayout(_:)`.
    public private(set) var layout: CombineLayout

    /// A canvas holding one capture.
    public init(imageSize: PixelSize, scale: Double, imageID: UUID = UUID()) {
        self.scale = scale
        images = [CanvasImage(id: imageID, pixelSize: imageSize)]
        layout = .standard(scale: scale)
    }

    /// Projects saved before Combine have no layout; they get the standard one.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        scale = try container.decode(Double.self, forKey: .scale)
        images = try container.decode([CanvasImage].self, forKey: .images)
        annotations = try container.decode([Annotation].self, forKey: .annotations)
        background = try container.decode(RGBAColor.self, forKey: .background)
        layout = try container.decodeIfPresent(CombineLayout.self, forKey: .layout) ?? .standard(scale: scale)
    }

    /// The flattened image's size: everything the captures cover, from (0, 0).
    public var canvasSize: PixelSize {
        PixelSize(
            width: images.map(\.frame.maxX).max() ?? 0,
            height: images.map(\.frame.maxY).max() ?? 0
        )
    }

    public var canvasRect: CGRect {
        CGRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height)
    }

    // MARK: - Captures

    public func image(_ id: UUID) -> CanvasImage? { images.first { $0.id == id } }

    /// The capture under `p`, topmost first.
    public func image(at p: CGPoint) -> CanvasImage? {
        images.last { $0.frame.cgRect.contains(p) }
    }

    /// Crops capture `id` to `rect`, in the capture's own pixels; nothing happens if
    /// `rect` misses it. Annotations drawn on it stay on the same pixels, and the
    /// other captures close up around its new size.
    public mutating func crop(_ id: UUID, to rect: PixelRect) {
        guard let index = images.firstIndex(where: { $0.id == id }),
              let rect = rect.clamped(to: images[index].pixelSize)
        else { return }
        let layout = layout
        moveImages {
            $0[index].crop = rect
            layout.place(&$0)
        }
    }

    /// Combine: adds a capture after the others (decision 3).
    public mutating func append(imageOf size: PixelSize, id: UUID = UUID()) {
        let layout = layout
        moveImages {
            $0.append(CanvasImage(id: id, pixelSize: size))
            layout.place(&$0)
        }
    }

    /// Takes a capture off the canvas with the annotations drawn on it. The last
    /// capture stays.
    public mutating func removeImage(_ id: UUID) {
        guard images.count > 1, images.contains(where: { $0.id == id }) else { return }
        annotations.removeAll { $0.anchor == id }
        let layout = layout
        moveImages {
            $0.removeAll { $0.id == id }
            layout.place(&$0)
        }
    }

    /// Lays the captures out again; their annotations move with them.
    public mutating func setLayout(_ layout: CombineLayout) {
        self.layout = layout
        moveImages { layout.place(&$0) }
    }

    /// What the crop tool shows: capture `id` alone and uncropped at the origin, with
    /// the annotations drawn on it, so a crop can grow back out as well as in.
    public func uncropped(_ id: UUID) -> EditorDocument? {
        guard let index = images.firstIndex(where: { $0.id == id }) else { return nil }
        var preview = self
        preview.annotations = annotations.filter { $0.anchor == id }
        preview.images = [images[index]]
        preview.moveImages {
            $0[0].crop = PixelRect(x: 0, y: 0, width: $0[0].pixelSize.width, height: $0[0].pixelSize.height)
            $0[0].origin = PixelPoint(x: 0, y: 0)
        }
        return preview
    }

    /// Changes capture placement (crop or position) and carries each capture's
    /// annotations along by however far its pixels moved.
    mutating func moveImages(_ change: (inout [CanvasImage]) -> Void) {
        let before = Dictionary(uniqueKeysWithValues: images.map { ($0.id, $0.offset) })
        change(&images)
        let after = Dictionary(uniqueKeysWithValues: images.map { ($0.id, $0.offset) })
        for index in annotations.indices {
            guard let anchor = annotations[index].anchor, let old = before[anchor], let new = after[anchor] else {
                continue
            }
            annotations[index] = annotations[index].moved(dx: Double(new.x - old.x), dy: Double(new.y - old.y))
        }
    }

    // MARK: - Annotations

    public func annotation(_ id: UUID) -> Annotation? { annotations.first { $0.id == id } }

    /// Adds `annotation` on top, anchored to the capture under its first point.
    public mutating func add(_ annotation: Annotation) {
        var annotation = annotation
        if annotation.anchor == nil { annotation.anchor = image(at: annotation.start)?.id }
        annotations.append(annotation)
    }

    /// Replaces the annotation with the same id.
    public mutating func update(_ annotation: Annotation) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        annotations[index] = annotation
    }

    public mutating func remove(_ id: UUID) {
        annotations.removeAll { $0.id == id }
    }

    public struct Hit: Hashable, Sendable {
        public let id: UUID
        public let part: Annotation.Part
    }

    /// The annotation under `p`, topmost first. The selected annotation's handles
    /// win over everything, since they are drawn on top.
    public func hit(_ p: CGPoint, tolerance: Double, selected: UUID?) -> Hit? {
        if let selected, let annotation = annotation(selected) {
            for (part, point) in annotation.handles where hypot(point.x - p.x, point.y - p.y) <= tolerance {
                return Hit(id: selected, part: part)
            }
        }
        for annotation in annotations.reversed()
        where annotation.contains(p, tolerance: tolerance, selected: annotation.id == selected) {
            return Hit(id: annotation.id, part: .body)
        }
        return nil
    }
}
