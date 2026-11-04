import CoreGraphics
import Foundation

public enum Pixelation {
    /// Mosaic cell size for a canvas at `scale`: 8 points, coarse enough that text
    /// under it can't be read by eye.
    public static func blockSize(scale: Double) -> Int { max(4, Int((8 * scale).rounded())) }

    /// `image` with every `block` × `block` cell, counted from its top-left corner,
    /// filled with that cell's average color.
    public static func mosaic(_ image: CGImage, block: Int) -> CGImage? {
        let width = image.width, height = image.height
        guard block > 0, let context = CanvasRenderer.bitmap(width: width, height: height, space: image.colorSpace),
              let data = context.data
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytesPerRow = context.bytesPerRow
        // A bitmap context keeps its top row first, so rows count down like the canvas.
        let pixels = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
        for top in stride(from: 0, to: height, by: block) {
            let bottom = min(top + block, height)
            for left in stride(from: 0, to: width, by: block) {
                let right = min(left + block, width)
                var sum = (0, 0, 0, 0)
                for y in top..<bottom {
                    for x in left..<right {
                        let i = y * bytesPerRow + x * 4
                        sum.0 += Int(pixels[i]); sum.1 += Int(pixels[i + 1])
                        sum.2 += Int(pixels[i + 2]); sum.3 += Int(pixels[i + 3])
                    }
                }
                let count = (bottom - top) * (right - left)
                let average = [sum.0, sum.1, sum.2, sum.3].map { UInt8(($0 + count / 2) / count) }
                for y in top..<bottom {
                    for x in left..<right {
                        let i = y * bytesPerRow + x * 4
                        pixels[i] = average[0]; pixels[i + 1] = average[1]
                        pixels[i + 2] = average[2]; pixels[i + 3] = average[3]
                    }
                }
            }
        }
        return context.makeImage()
    }
}

/// Draws an EditorDocument. The editor's canvas and the exported PNG both come from
/// here, so what you see is what gets saved. Every context it draws into is in canvas
/// pixels with the y axis pointing down.
public enum CanvasRenderer {
    /// The finished image: the captures, then each pixelate — which really replaces
    /// the pixels under it, so the PNG never holds them — then arrows, rectangles and
    /// text on top.
    public static func flatten(_ document: EditorDocument, images: [UUID: CGImage]) -> CGImage? {
        let size = document.canvasSize
        guard let context = canvasContext(size: size, space: colorSpace(of: images)) else { return nil }
        var covers: [UUID: CGImage] = [:]
        for annotation in document.annotations where annotation.kind == .pixelate {
            covers[annotation.id] = cover(for: annotation, in: document, images: images)
        }
        draw(document, images: images, covers: covers, in: context)
        return context.makeImage()
    }

    /// Draws the whole document. `covers` holds each mosaic pixelate's tile (from
    /// `cover(for:in:images:)`); the editor caches them between redraws. `hiding`
    /// leaves one annotation out — the text being typed.
    public static func draw(
        _ document: EditorDocument, images: [UUID: CGImage], covers: [UUID: CGImage], hiding: UUID? = nil,
        in context: CGContext
    ) {
        drawCaptures(document, images: images, in: context)
        for annotation in document.annotations where annotation.kind == .pixelate && annotation.id != hiding {
            guard let region = pixelRegion(of: annotation, in: document) else { continue }
            if annotation.cover == .mosaic, let tile = covers[annotation.id] {
                drawImage(tile, in: region.cgRect, context: context)
            } else {
                // Opaque even if the color isn't, so nothing shows through.
                context.setFillColor(annotation.color.opaque.cgColor)
                context.fill(region.cgRect)
            }
        }
        for annotation in document.annotations where annotation.kind != .pixelate && annotation.id != hiding {
            drawMarkup(annotation, in: context)
        }
    }

    /// The background and every capture, each cut to its crop.
    public static func drawCaptures(_ document: EditorDocument, images: [UUID: CGImage], in context: CGContext) {
        context.setFillColor(document.background.cgColor)
        context.fill(document.canvasRect)
        for image in document.images {
            guard let pixels = images[image.id]?.cropping(to: image.crop.cgRect) else { continue }
            drawImage(pixels, in: image.frame.cgRect, context: context)
        }
    }

    /// The canvas pixels a pixelate covers: its rectangle rounded out to whole pixels
    /// and cut to the canvas.
    public static func pixelRegion(of annotation: Annotation, in document: EditorDocument) -> PixelRect? {
        let r = annotation.rect
        let x0 = Int(r.minX.rounded(.down)), y0 = Int(r.minY.rounded(.down))
        let x1 = Int(r.maxX.rounded(.up)), y1 = Int(r.maxY.rounded(.up))
        return PixelRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0).clamped(to: document.canvasSize)
    }

    /// A mosaic pixelate's tile: the captures under it, averaged into blocks. Nil for
    /// solid ones, which are just filled.
    public static func cover(for annotation: Annotation, in document: EditorDocument, images: [UUID: CGImage]) -> CGImage? {
        guard annotation.kind == .pixelate, annotation.cover == .mosaic,
              let region = pixelRegion(of: annotation, in: document),
              let context = canvasContext(size: region.size, space: colorSpace(of: images))
        else { return nil }
        // Sample the captures only, never other annotations, so overlapping pixelates
        // don't depend on their order.
        context.translateBy(x: CGFloat(-region.x), y: CGFloat(-region.y))
        drawCaptures(document, images: images, in: context)
        guard let under = context.makeImage() else { return nil }
        return Pixelation.mosaic(under, block: Pixelation.blockSize(scale: document.scale))
    }

    /// An arrow, rectangle or text annotation.
    public static func drawMarkup(_ annotation: Annotation, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        let color = annotation.color.cgColor
        switch annotation.kind {
        case .arrow:
            context.addPath(ArrowShape.path(from: annotation.start, to: annotation.end, width: annotation.size))
            context.setFillColor(color)
            context.fillPath()
        case .rectangle:
            context.setStrokeColor(color)
            context.setLineWidth(annotation.size)
            context.setLineJoin(.miter)
            context.stroke(annotation.rect)
        case .text:
            TextLayout.draw(annotation.text, fontSize: annotation.size, color: color, at: annotation.start, in: context)
        case .pixelate:
            break
        }
    }

    // MARK: - Contexts

    /// The capture's own color space when a bitmap can use it, so exporting doesn't
    /// shift colors; sRGB otherwise.
    static func colorSpace(of images: [UUID: CGImage]) -> CGColorSpace? {
        images.values.lazy.compactMap(\.colorSpace).first { $0.model == .rgb }
    }

    /// An RGBA bitmap in `space`, falling back to sRGB. Default (y-up) coordinates.
    static func bitmap(width: Int, height: Int, space: CGColorSpace?) -> CGContext? {
        let spaces = [space, CGColorSpace(name: CGColorSpace.sRGB)].compactMap { $0 }.filter { $0.model == .rgb }
        for space in spaces {
            if let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) { return context }
        }
        return nil
    }

    /// A bitmap flipped to canvas coordinates: top-left origin, y down. Captures land
    /// on whole pixels at their own size, so nothing is resampled.
    static func canvasContext(size: PixelSize, space: CGColorSpace?) -> CGContext? {
        guard size.width > 0, size.height > 0,
              let context = bitmap(width: size.width, height: size.height, space: space)
        else { return nil }
        context.translateBy(x: 0, y: CGFloat(size.height))
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .none
        return context
    }

    /// CGImage draws y-up; in a y-down context it would land upside down.
    static func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }
}

extension ImageScaling {
    /// `image` redrawn at exactly `size` pixels, up or down — a 1x capture joining a
    /// 2x canvas is doubled so both show at the same size.
    public static func resized(_ image: CGImage, to size: PixelSize) -> CGImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        if size == PixelSize(width: image.width, height: image.height) { return image }
        guard let context = CanvasRenderer.bitmap(width: size.width, height: size.height, space: image.colorSpace) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return context.makeImage()
    }
}
