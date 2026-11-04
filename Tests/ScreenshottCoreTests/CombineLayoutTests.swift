import CoreGraphics
import Foundation
import Testing
@testable import ScreenshottCore

private let sizes = [PixelSize(width: 100, height: 50), PixelSize(width: 60, height: 80), PixelSize(width: 80, height: 10)]

@Test func columnStacksTopToBottomWithTheGap() {
    let layout = CombineLayout(direction: .vertical, alignment: .leading, spacing: 10)
    #expect(layout.origins(for: sizes) == [PixelPoint(x: 0, y: 0), PixelPoint(x: 0, y: 60), PixelPoint(x: 0, y: 150)])
}

@Test func columnCentersAndRightAlignsAgainstTheWidest() {
    let center = CombineLayout(direction: .vertical, alignment: .center, spacing: 0).origins(for: sizes)
    #expect(center.map(\.x) == [0, 20, 10])
    let trailing = CombineLayout(direction: .vertical, alignment: .trailing, spacing: 0).origins(for: sizes)
    #expect(trailing.map(\.x) == [0, 40, 20])
}

@Test func rowGoesLeftToRightAndAlignsVertically() {
    let layout = CombineLayout(direction: .horizontal, alignment: .trailing, spacing: 5)
    #expect(layout.origins(for: sizes) == [PixelPoint(x: 0, y: 30), PixelPoint(x: 105, y: 0), PixelPoint(x: 170, y: 70)])
}

@Test func negativeSpacingCountsAsNone() {
    let layout = CombineLayout(direction: .vertical, alignment: .leading, spacing: -20)
    #expect(layout.origins(for: sizes).map(\.y) == [0, 50, 130])
}

@Test func standardLayoutIsALeftAlignedColumnSixteenPointsApart() {
    #expect(CombineLayout.standard(scale: 2) == CombineLayout(direction: .vertical, alignment: .leading, spacing: 32))
}

@Test func appendedCaptureGoesBelowAndGrowsTheCanvas() {
    let first = UUID(), second = UUID()
    var doc = EditorDocument(imageSize: PixelSize(width: 100, height: 50), scale: 1, imageID: first)
    doc.append(imageOf: PixelSize(width: 200, height: 40), id: second)
    #expect(doc.image(second)?.origin == PixelPoint(x: 0, y: 66))
    #expect(doc.canvasSize == PixelSize(width: 200, height: 106))
}

@Test func relayoutCarriesAnnotationsWithTheirCapture() {
    let first = UUID(), second = UUID()
    var doc = EditorDocument(imageSize: PixelSize(width: 100, height: 50), scale: 1, imageID: first)
    doc.append(imageOf: PixelSize(width: 200, height: 40), id: second)
    doc.add(Annotation(kind: .arrow, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 30, y: 30), size: 4))
    doc.add(Annotation(kind: .arrow, start: CGPoint(x: 150, y: 80), end: CGPoint(x: 160, y: 90), size: 4))
    #expect(doc.annotations.map(\.anchor) == [first, second])

    doc.setLayout(CombineLayout(direction: .vertical, alignment: .center, spacing: 16))
    #expect(doc.image(first)?.origin == PixelPoint(x: 50, y: 0))
    #expect(doc.annotations[0].start == CGPoint(x: 60, y: 10))
    #expect(doc.annotations[1].start == CGPoint(x: 150, y: 80))

    doc.setLayout(CombineLayout(direction: .horizontal, alignment: .leading, spacing: 0))
    #expect(doc.image(second)?.origin == PixelPoint(x: 100, y: 0))
    #expect(doc.annotations[1].start == CGPoint(x: 250, y: 14))
}

@Test func croppingOneCaptureClosesUpTheOthers() {
    let first = UUID(), second = UUID()
    var doc = EditorDocument(imageSize: PixelSize(width: 100, height: 50), scale: 1, imageID: first)
    doc.append(imageOf: PixelSize(width: 100, height: 50), id: second)
    doc.add(Annotation(kind: .arrow, start: CGPoint(x: 10, y: 80), end: CGPoint(x: 20, y: 90), size: 4))
    doc.crop(first, to: PixelRect(x: 0, y: 30, width: 100, height: 20))
    #expect(doc.image(second)?.origin == PixelPoint(x: 0, y: 36))
    #expect(doc.annotations[0].start == CGPoint(x: 10, y: 50))
}

@Test func removingACaptureTakesItsAnnotationsAndKeepsTheLastOne() {
    let first = UUID(), second = UUID()
    var doc = EditorDocument(imageSize: PixelSize(width: 100, height: 50), scale: 1, imageID: first)
    doc.append(imageOf: PixelSize(width: 100, height: 50), id: second)
    doc.add(Annotation(kind: .arrow, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 20, y: 20), size: 4))
    doc.add(Annotation(kind: .arrow, start: CGPoint(x: 10, y: 80), end: CGPoint(x: 20, y: 90), size: 4))
    doc.removeImage(first)
    #expect(doc.images.map(\.id) == [second])
    #expect(doc.image(second)?.origin == PixelPoint(x: 0, y: 0))
    #expect(doc.annotations.count == 1)
    #expect(doc.annotations[0].start == CGPoint(x: 10, y: 14))
    doc.removeImage(second)
    #expect(doc.images.count == 1)
}

@Test func projectsFromBeforeCombineGetTheStandardLayout() throws {
    let doc = EditorDocument(imageSize: PixelSize(width: 10, height: 10), scale: 2)
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(doc)) as! [String: Any]
    json["layout"] = nil
    let decoded = try JSONDecoder().decode(EditorDocument.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(decoded.layout == .standard(scale: 2))
    #expect(decoded == doc)
}

@Test func flattenedCombinedCanvasFillsTheGapWithTheBackground() throws {
    let first = UUID(), second = UUID()
    var doc = EditorDocument(imageSize: PixelSize(width: 4, height: 2), scale: 1, imageID: first)
    doc.setLayout(CombineLayout(direction: .vertical, alignment: .leading, spacing: 3))
    doc.append(imageOf: PixelSize(width: 2, height: 2), id: second)
    let image = patternImage(width: 4, height: 2)
    let flat = try #require(CanvasRenderer.flatten(doc, images: [first: image, second: image]))
    #expect(flat.width == 4 && flat.height == 7)
    let pixels = rgba(flat)
    #expect(pixels[3 * 4] == [255, 255, 255, 255])
    #expect(pixels[5 * 4] == rgba(image)[0])
    #expect(pixels[5 * 4 + 3] == [255, 255, 255, 255])
}

@Test func resizedDoublesA1xCapture() throws {
    let image = patternImage(width: 3, height: 2)
    let doubled = try #require(ImageScaling.resized(image, to: PixelSize(width: 6, height: 4)))
    #expect(doubled.width == 6 && doubled.height == 4)
    #expect(ImageScaling.resized(image, to: PixelSize(width: 3, height: 2)) === image)
}
