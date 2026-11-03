import CoreGraphics
import Testing
@testable import ScreenshottCore

private func image(width: Int, height: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

@Test func retinaCaptureHalvesToLogicalSize() {
    let scaled = ImageScaling.downscaled(image(width: 200, height: 100), by: 2)
    #expect(scaled?.width == 100)
    #expect(scaled?.height == 50)
}

@Test func oneXCaptureIsLeftAlone() {
    let original = image(width: 64, height: 32)
    #expect(ImageScaling.downscaled(original, by: 1) === original)
}

@Test func oddSizesRoundAndNeverReachZero() {
    #expect(ImageScaling.downscaled(image(width: 3, height: 1), by: 2)?.width == 2)
    #expect(ImageScaling.downscaled(image(width: 3, height: 1), by: 2)?.height == 1)
}
