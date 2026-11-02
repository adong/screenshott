import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum PNGEncoder {
    /// Encodes `image` as PNG tagged with 72 × `scale` DPI. Without the tag a Retina
    /// capture opens at double size in Preview, Keynote and friends — the same
    /// metadata the system's own screenshots carry.
    public static func data(from image: CGImage, scale: CGFloat) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }

        let dpi = 72.0 * Double(scale)
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
