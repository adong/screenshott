import CoreGraphics

public enum ImageScaling {
    /// `image` redrawn at 1 / `factor` of its pixel size — Retina captures saved at
    /// their logical size, the opt-out from decision 4b. At `factor` 1 or less it
    /// returns `image` untouched.
    public static func downscaled(_ image: CGImage, by factor: CGFloat) -> CGImage? {
        guard factor > 1 else { return image }
        let width = max(1, Int((CGFloat(image.width) / factor).rounded()))
        let height = max(1, Int((CGFloat(image.height) / factor).rounded()))
        // Keep the capture's color space when a bitmap context can use it.
        let spaces = [image.colorSpace, CGColorSpace(name: CGColorSpace.sRGB)].compactMap { $0 }
        for space in spaces {
            guard let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { continue }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return context.makeImage()
        }
        return nil
    }
}
