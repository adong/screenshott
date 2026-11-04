import CoreGraphics
import Foundation
import Testing
@testable import ScreenshottCore

private let imageID = UUID()

private func document() -> EditorDocument {
    EditorDocument(imageSize: PixelSize(width: 400, height: 300), scale: 2, imageID: imageID)
}

private func arrow(from a: CGPoint, to b: CGPoint) -> Annotation {
    Annotation(kind: .arrow, start: a, end: b, size: 8)
}

@Test func aNewDocumentIsOneUncroppedCaptureAtTheOrigin() {
    let doc = document()
    #expect(doc.canvasSize == PixelSize(width: 400, height: 300))
    #expect(doc.images.first?.crop == PixelRect(x: 0, y: 0, width: 400, height: 300))
    #expect(doc.images.first?.frame == PixelRect(x: 0, y: 0, width: 400, height: 300))
}

@Test func addingAnchorsToTheCaptureUnderTheFirstPoint() {
    var doc = document()
    doc.add(arrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 900, y: 900)))
    doc.add(arrow(from: CGPoint(x: 500, y: 10), to: CGPoint(x: 20, y: 20)))
    #expect(doc.annotations[0].anchor == imageID)
    #expect(doc.annotations[1].anchor == nil)
}

@Test func croppingMovesAnnotationsWithTheirPixels() {
    var doc = document()
    doc.add(arrow(from: CGPoint(x: 150, y: 120), to: CGPoint(x: 200, y: 160)))
    doc.crop(imageID, to: PixelRect(x: 100, y: 100, width: 200, height: 100))
    #expect(doc.canvasSize == PixelSize(width: 200, height: 100))
    #expect(doc.annotations[0].start == CGPoint(x: 50, y: 20))
    #expect(doc.annotations[0].end == CGPoint(x: 100, y: 60))

    // Uncropping (re-editing the crop) puts it back where it was.
    doc.crop(imageID, to: PixelRect(x: 0, y: 0, width: 400, height: 300))
    #expect(doc.annotations[0].start == CGPoint(x: 150, y: 120))
}

@Test func cropIsCutToTheCaptureAndIgnoredWhenItMisses() {
    var doc = document()
    doc.crop(imageID, to: PixelRect(x: 300, y: -50, width: 500, height: 100))
    #expect(doc.images[0].crop == PixelRect(x: 300, y: 0, width: 100, height: 50))
    doc.crop(imageID, to: PixelRect(x: 900, y: 900, width: 10, height: 10))
    #expect(doc.images[0].crop == PixelRect(x: 300, y: 0, width: 100, height: 50))
}

@Test func uncroppedShowsOneWholeCaptureWithItsOwnAnnotations() throws {
    var doc = document()
    doc.add(arrow(from: CGPoint(x: 150, y: 120), to: CGPoint(x: 200, y: 160)))
    doc.add(arrow(from: CGPoint(x: 900, y: 900), to: CGPoint(x: 950, y: 950)))  // on no capture
    doc.crop(imageID, to: PixelRect(x: 100, y: 100, width: 200, height: 100))
    let preview = try #require(doc.uncropped(imageID))
    #expect(preview.canvasSize == PixelSize(width: 400, height: 300))
    #expect(preview.annotations.count == 1)
    #expect(preview.annotations[0].start == CGPoint(x: 150, y: 120))
    #expect(doc.uncropped(UUID()) == nil)
}

@Test func hitFindsTheTopmostAnnotation() {
    var doc = document()
    let bottom = Annotation(kind: .pixelate, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100), size: 0)
    let top = Annotation(kind: .pixelate, start: CGPoint(x: 50, y: 50), end: CGPoint(x: 150, y: 150), size: 0)
    doc.add(bottom)
    doc.add(top)
    #expect(doc.hit(CGPoint(x: 75, y: 75), tolerance: 4, selected: nil) == .init(id: top.id, part: .body))
    #expect(doc.hit(CGPoint(x: 25, y: 25), tolerance: 4, selected: nil) == .init(id: bottom.id, part: .body))
    #expect(doc.hit(CGPoint(x: 300, y: 250), tolerance: 4, selected: nil) == nil)
}

@Test func theSelectedAnnotationsHandlesWinOverWhatIsAboveIt() {
    var doc = document()
    let below = Annotation(kind: .rectangle, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 100, y: 100), size: 4)
    let above = Annotation(kind: .pixelate, start: CGPoint(x: 80, y: 80), end: CGPoint(x: 200, y: 200), size: 0)
    doc.add(below)
    doc.add(above)
    let corner = CGPoint(x: 101, y: 99)
    #expect(doc.hit(corner, tolerance: 4, selected: nil)?.id == above.id)
    #expect(doc.hit(corner, tolerance: 4, selected: below.id) == .init(id: below.id, part: .handle(.bottomRight)))
}

@Test func updateAndRemoveWorkById() {
    var doc = document()
    var a = arrow(from: .zero, to: CGPoint(x: 50, y: 50))
    doc.add(a)
    a.color = .black
    doc.update(a)
    #expect(doc.annotation(a.id)?.color == .black)
    doc.remove(a.id)
    #expect(doc.annotations.isEmpty)
}

@Test func documentRoundTripsThroughJSON() throws {
    var doc = document()
    doc.add(Annotation(kind: .text, start: CGPoint(x: 5, y: 6), end: CGPoint(x: 5, y: 6), size: 40, text: "Hi\nthere"))
    doc.add(Annotation(kind: .pixelate, start: CGPoint(x: 1, y: 2), end: CGPoint(x: 30, y: 40), size: 0, cover: .solid))
    doc.crop(imageID, to: PixelRect(x: 1, y: 1, width: 300, height: 200))
    let data = try JSONEncoder().encode(doc)
    #expect(try JSONDecoder().decode(EditorDocument.self, from: data) == doc)
}
