import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ScreenshottCore

private func solidImage(width: Int, height: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

private func properties(of data: Data) -> [CFString: Any] {
    let source = CGImageSourceCreateWithData(data as CFData, nil)!
    return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
}

@Test func retinaCaptureIsTaggedAt144DPI() throws {
    let data = try #require(PNGEncoder.data(from: solidImage(width: 8, height: 4), scale: 2))
    let props = properties(of: data)
    #expect(props[kCGImagePropertyPixelWidth] as? Int == 8)
    #expect(props[kCGImagePropertyPixelHeight] as? Int == 4)
    #expect(props[kCGImagePropertyDPIWidth] as? Double == 144)
    #expect(props[kCGImagePropertyDPIHeight] as? Double == 144)
}

@Test func outputIsPNG() throws {
    let data = try #require(PNGEncoder.data(from: solidImage(width: 2, height: 2), scale: 1))
    #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
}
