import CoreGraphics

/// One captured pixel's color in sRGB: what the overlay's color picker shows and ⌘C
/// copies. A capture comes in the display's own color space (often Display P3), and
/// color values pasted into design tools are taken as sRGB, so the pixel is converted.
public struct PixelColor: Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// "#3A7BD5".
    public var hex: String {
        let digits = Array("0123456789ABCDEF")
        return "#" + [red, green, blue].map { "\(digits[Int($0 >> 4)])\(digits[Int($0 & 15)])" }.joined()
    }

    /// "rgb(58, 123, 213)", as CSS writes it.
    public var rgb: String { "rgb(\(red), \(green), \(blue))" }

    public var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }

    /// The pixel at `p` (top-left origin) of `image`, or nil outside it.
    public static func at(_ p: PixelPoint, in image: CGImage) -> PixelColor? {
        guard p.x >= 0, p.y >= 0, p.x < image.width, p.y < image.height,
              let pixel = image.cropping(to: CGRect(x: p.x, y: p.y, width: 1, height: 1)),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        // Drawing into an sRGB bitmap converts from the capture's color space.
        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let bytes = context.data?.bindMemory(to: UInt8.self, capacity: 4) else { return nil }
        return PixelColor(red: bytes[0], green: bytes[1], blue: bytes[2])
    }
}
