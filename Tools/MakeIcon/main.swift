import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Draws the Screenshott app icon at every size an .iconset needs, as vectors per size
// rather than downsampling one bitmap, so 16 px stays crisp.
//
//   MakeIcon <dir.iconset>   then   iconutil -c icns <dir.iconset>
//
// Geometry is in 1024-unit space, origin bottom-left, on Apple's macOS icon grid:
// an 824-unit body centred on the canvas, leaving room for the drop shadow.

enum Icon {
    static var sRGB: CGColorSpace { CGColorSpace(name: CGColorSpace.sRGB)! }

    static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// Superellipse |x/a|^n + |y/b|^n = 1 — the continuous-corner "squircle" shape of
    /// macOS icons, which a plain rounded rect only approximates.
    static func squircle(in rect: CGRect, n: CGFloat = 5) -> CGPath {
        let path = CGMutablePath()
        let steps = 720
        for i in 0..<steps {
            let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
            let c = cos(t), s = sin(t)
            let point = CGPoint(
                x: rect.midX + rect.width / 2 * copysign(pow(abs(c), 2 / n), c),
                y: rect.midY + rect.height / 2 * copysign(pow(abs(s), 2 / n), s)
            )
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    static func gradient(_ stops: [(UInt32, CGFloat)]) -> CGGradient {
        CGGradient(
            colorsSpace: sRGB,
            colors: stops.map { color($0.0) } as CFArray,
            locations: stops.map(\.1)
        )!
    }

    /// `scale` is pixels per design unit. Shadow offset and blur ignore the CTM, so
    /// they are scaled by hand.
    static func draw(in ctx: CGContext, scale: CGFloat) {
        let small = scale * 1024 <= 32
        let body = CGRect(x: 100, y: 100, width: 824, height: 824)
        let shape = squircle(in: body)

        // Drop shadow under the body.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12 * scale), blur: 28 * scale, color: color(0x000000, 0.35))
        ctx.addPath(shape)
        ctx.setFillColor(color(0x3A2BB8))
        ctx.fillPath()
        ctx.restoreGState()

        // Body: violet → indigo → electric blue, with a soft sheen across the top.
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        ctx.drawLinearGradient(
            gradient([(0x8B6CFF, 0), (0x5B3FF0, 0.45), (0x1F7BFF, 1)]),
            start: CGPoint(x: 200, y: 924), end: CGPoint(x: 824, y: 100), options: []
        )
        ctx.drawLinearGradient(
            CGGradient(colorsSpace: sRGB, colors: [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!,
            start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 600), options: []
        )
        ctx.restoreGState()

        // The captured "shot": a window card with traffic lights and two text lines.
        let card = CGRect(x: 322, y: 372, width: 380, height: 280)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 30 * scale, color: color(0x150A5C, 0.45))
        ctx.addPath(CGPath(roundedRect: card, cornerWidth: 40, cornerHeight: 40, transform: nil))
        ctx.setFillColor(color(0xFFFFFF))
        ctx.fillPath()
        ctx.restoreGState()

        if !small {
            for (i, hex) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
                let center = CGPoint(x: 372 + CGFloat(i) * 46, y: 606)
                ctx.addEllipse(in: CGRect(x: center.x - 15, y: center.y - 15, width: 30, height: 30))
                ctx.setFillColor(color(UInt32(hex)))
                ctx.fillPath()
            }
            // A photo tile — sun over a mountain — so the card reads as captured content.
            let tile = CGRect(x: 356, y: 410, width: 150, height: 150)
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: tile, cornerWidth: 22, cornerHeight: 22, transform: nil))
            ctx.clip()
            ctx.drawLinearGradient(
                gradient([(0xE6E0FF, 0), (0xC9D9FF, 1)]),
                start: CGPoint(x: tile.midX, y: tile.maxY), end: CGPoint(x: tile.midX, y: tile.minY), options: []
            )
            ctx.addEllipse(in: CGRect(x: 446, y: 500, width: 36, height: 36))
            ctx.setFillColor(color(0xFFB547))
            ctx.fillPath()
            let mountain = CGMutablePath()
            mountain.move(to: CGPoint(x: tile.minX - 10, y: tile.minY))
            mountain.addLine(to: CGPoint(x: 412, y: 498))
            mountain.addLine(to: CGPoint(x: 456, y: 452))
            mountain.addLine(to: CGPoint(x: 478, y: 474))
            mountain.addLine(to: CGPoint(x: tile.maxX + 10, y: tile.minY))
            mountain.closeSubpath()
            ctx.addPath(mountain)
            ctx.setFillColor(color(0x7A62FF))
            ctx.fillPath()
            ctx.restoreGState()

            for (y, width) in [(526.0, 140.0), (480.0, 104.0), (434.0, 124.0)] {
                ctx.addPath(CGPath(
                    roundedRect: CGRect(x: 530, y: y, width: width, height: 24),
                    cornerWidth: 12, cornerHeight: 12, transform: nil
                ))
                ctx.setFillColor(color(0xD3CBFF))
                ctx.fillPath()
            }
        }

        // Viewfinder brackets framing the shot.
        let frame = CGRect(x: 222, y: 222, width: 580, height: 580)
        let arm: CGFloat = 150
        let brackets = CGMutablePath()
        for (corner, dx, dy) in [
            (CGPoint(x: frame.minX, y: frame.maxY), 1.0, -1.0),
            (CGPoint(x: frame.maxX, y: frame.maxY), -1.0, -1.0),
            (CGPoint(x: frame.minX, y: frame.minY), 1.0, 1.0),
            (CGPoint(x: frame.maxX, y: frame.minY), -1.0, 1.0),
        ] {
            brackets.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
            brackets.addLine(to: corner)
            brackets.addLine(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
        }
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6 * scale), blur: 16 * scale, color: color(0x150A5C, 0.35))
        ctx.addPath(brackets)
        ctx.setStrokeColor(color(0xFFFFFF))
        ctx.setLineWidth(small ? 72 : 54)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.restoreGState()
    }

    static func render(pixels: Int) -> CGImage {
        let ctx = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let scale = CGFloat(pixels) / 1024
        ctx.scaleBy(x: scale, y: scale)
        draw(in: ctx, scale: scale)
        return ctx.makeImage()!
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Support/AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for (points, factor) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = "icon_\(points)x\(points)\(factor == 2 ? "@2x" : "").png"
    try Icon.writePNG(Icon.render(pixels: points * factor), to: output.appendingPathComponent(name))
}
print("wrote \(output.path)")
