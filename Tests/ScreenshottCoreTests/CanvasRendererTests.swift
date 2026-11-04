import CoreGraphics
import Foundation
import Testing
@testable import ScreenshottCore

/// An opaque image where every pixel differs from its neighbours: red counts x, green
/// counts y, blue alternates — what a line of text looks like to a pixelate.
func patternImage(width: Int, height: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let pixels = context.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let i = (y * width + x) * 4
            pixels[i] = UInt8(x % 256); pixels[i + 1] = UInt8(y % 256)
            pixels[i + 2] = (x + y) % 2 == 0 ? 255 : 0; pixels[i + 3] = 255
        }
    }
    return context.makeImage()!
}

/// RGBA of every pixel, top row first.
func rgba(_ image: CGImage) -> [[UInt8]] {
    let width = image.width, height = image.height
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let pixels = context.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
    return (0..<width * height).map { i in (0..<4).map { pixels[i * 4 + $0] } }
}

private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
    rgba(image)[y * image.width + x]
}

@Test func mosaicFillsEachBlockWithItsAverage() throws {
    let image = patternImage(width: 8, height: 4)
    let mosaic = try #require(Pixelation.mosaic(image, block: 4))
    let pixels = rgba(mosaic)
    // Left block: x 0...3 → red averages 1.5 (rounds to 2), y 0...3 → green 1.5 → 2.
    #expect(pixels[0] == [2, 2, 128, 255])
    #expect(pixels[3 * 8 + 3] == [2, 2, 128, 255])
    // Right block: red averages 5.5 → 6.
    #expect(pixels[7] == [6, 2, 128, 255])
}

@Test func mosaicHandlesAPartialLastBlock() throws {
    let mosaic = try #require(Pixelation.mosaic(patternImage(width: 5, height: 1), block: 4))
    #expect(rgba(mosaic)[4] == [4, 0, 255, 255])
}

@Test func blockSizeIsEightPointsAndNeverTiny() {
    #expect(Pixelation.blockSize(scale: 2) == 16)
    #expect(Pixelation.blockSize(scale: 1) == 8)
    #expect(Pixelation.blockSize(scale: 0.25) == 4)
}

@Test func flatteningAnUneditedCaptureIsPixelExact() throws {
    let image = patternImage(width: 40, height: 30)
    let id = UUID()
    let doc = EditorDocument(imageSize: PixelSize(width: 40, height: 30), scale: 1, imageID: id)
    let flat = try #require(CanvasRenderer.flatten(doc, images: [id: image]))
    #expect(rgba(flat) == rgba(image))
}

@Test func flatteningAppliesTheCrop() throws {
    let image = patternImage(width: 40, height: 30)
    let id = UUID()
    var doc = EditorDocument(imageSize: PixelSize(width: 40, height: 30), scale: 1, imageID: id)
    doc.crop(id, to: PixelRect(x: 10, y: 5, width: 20, height: 10))
    let flat = try #require(CanvasRenderer.flatten(doc, images: [id: image]))
    #expect(flat.width == 20 && flat.height == 10)
    #expect(pixel(flat, 0, 0) == pixel(image, 10, 5))
    #expect(pixel(flat, 19, 9) == pixel(image, 29, 14))
}

@Test func mosaicReallyReplacesThePixelsItCovers() throws {
    let image = patternImage(width: 64, height: 32)
    let id = UUID()
    var doc = EditorDocument(imageSize: PixelSize(width: 64, height: 32), scale: 1, imageID: id)
    doc.add(Annotation(kind: .pixelate, start: CGPoint(x: 8, y: 8), end: CGPoint(x: 24, y: 24), size: 0))
    let flat = try #require(CanvasRenderer.flatten(doc, images: [id: image]))
    let original = rgba(image), out = rgba(flat)
    // Inside: one 8 px block of the 16 px square is uniform, so the checker of blue
    // (the "text") is gone.
    let block = (8..<16).flatMap { y in (8..<16).map { x in out[y * 64 + x] } }
    #expect(Set(block).count == 1)
    #expect(block[0] != original[8 * 64 + 8])
    // Outside: untouched.
    #expect(out[0] == original[0])
    #expect(out[30 * 64 + 60] == original[30 * 64 + 60])
}

@Test func solidCoverPaintsOpaqueColorEvenFromATranslucentPick() throws {
    let image = patternImage(width: 32, height: 32)
    let id = UUID()
    var doc = EditorDocument(imageSize: PixelSize(width: 32, height: 32), scale: 1, imageID: id)
    doc.add(Annotation(
        kind: .pixelate, start: CGPoint(x: 4, y: 4), end: CGPoint(x: 20, y: 12),
        color: RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.3), size: 0, cover: .solid
    ))
    let flat = try #require(CanvasRenderer.flatten(doc, images: [id: image]))
    #expect(pixel(flat, 4, 4) == [0, 0, 0, 255])
    #expect(pixel(flat, 19, 11) == [0, 0, 0, 255])
    #expect(pixel(flat, 20, 12) == pixel(image, 20, 12))
}

@Test func pixelateRegionRoundsOutAndStaysOnTheCanvas() {
    let doc = EditorDocument(imageSize: PixelSize(width: 100, height: 50), scale: 1)
    let a = Annotation(kind: .pixelate, start: CGPoint(x: 10.4, y: -5), end: CGPoint(x: 20.2, y: 30.5), size: 0)
    #expect(CanvasRenderer.pixelRegion(of: a, in: doc) == PixelRect(x: 10, y: 0, width: 11, height: 31))
    let off = Annotation(kind: .pixelate, start: CGPoint(x: 200, y: 0), end: CGPoint(x: 300, y: 10), size: 0)
    #expect(CanvasRenderer.pixelRegion(of: off, in: doc) == nil)
}

@Test func markupIsDrawnAboveThePixelates() throws {
    let image = patternImage(width: 60, height: 60)
    let id = UUID()
    var doc = EditorDocument(imageSize: PixelSize(width: 60, height: 60), scale: 1, imageID: id)
    let red = RGBAColor(red: 1, green: 0, blue: 0)
    // A rectangle drawn first still shows over a solid pixelate drawn after it.
    doc.add(Annotation(kind: .rectangle, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 50, y: 50), color: red, size: 4))
    doc.add(Annotation(kind: .pixelate, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 60, y: 60), color: .white, size: 0, cover: .solid))
    let flat = try #require(CanvasRenderer.flatten(doc, images: [id: image]))
    #expect(pixel(flat, 10, 30) == [255, 0, 0, 255])
    #expect(pixel(flat, 30, 30) == [255, 255, 255, 255])
}

@Test func textAndArrowsLandWhereTheySay() throws {
    let id = UUID()
    var doc = EditorDocument(imageSize: PixelSize(width: 200, height: 100), scale: 1, imageID: id)
    let blank = CanvasRenderer.flatten(doc, images: [:])!
    let blue = RGBAColor(red: 0, green: 0, blue: 1)
    doc.add(Annotation(kind: .arrow, start: CGPoint(x: 10, y: 80), end: CGPoint(x: 90, y: 80), color: blue, size: 6))
    doc.add(Annotation(kind: .text, start: CGPoint(x: 110, y: 10), end: CGPoint(x: 110, y: 10), color: blue, size: 30, text: "Hi"))
    let flat = try #require(CanvasRenderer.flatten(doc, images: [:]))
    #expect(pixel(blank, 50, 80) == [255, 255, 255, 255])
    #expect(pixel(flat, 50, 80) == [0, 0, 255, 255])
    // Text sits below its top-left corner (y down), not mirrored above it.
    let textBox = rgba(flat).enumerated().filter { $0.offset % 200 >= 100 && $0.element != [255, 255, 255, 255] }
    let rows = textBox.map { $0.offset / 200 }
    #expect(rows.min()! >= 10)
    #expect(rows.max()! < 10 + Int(TextLayout.lineHeight(fontSize: 30)))
}
