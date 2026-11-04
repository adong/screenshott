import CoreGraphics
import Testing
@testable import ScreenshottCore

private func rectangle(_ r: CGRect, size: Double = 4) -> Annotation {
    Annotation(kind: .rectangle, start: r.origin, end: CGPoint(x: r.maxX, y: r.maxY), size: size)
}

@Test func rectSpansStartAndEndInEitherOrder() {
    let a = Annotation(kind: .pixelate, start: CGPoint(x: 50, y: 10), end: CGPoint(x: 20, y: 40), size: 0)
    #expect(a.rect == CGRect(x: 20, y: 10, width: 30, height: 30))
}

@Test func arrowCatchesPressesNearItsShaft() {
    let a = Annotation(kind: .arrow, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0), size: 4)
    #expect(a.contains(CGPoint(x: 50, y: 5), tolerance: 4, selected: false))
    #expect(!a.contains(CGPoint(x: 50, y: 9), tolerance: 4, selected: false))
    #expect(!a.contains(CGPoint(x: 110, y: 0), tolerance: 4, selected: false))
}

@Test func outlineRectangleOnlyCatchesItsLineUntilSelected() {
    let a = rectangle(CGRect(x: 0, y: 0, width: 100, height: 100))
    #expect(a.contains(CGPoint(x: 2, y: 50), tolerance: 4, selected: false))
    #expect(!a.contains(CGPoint(x: 50, y: 50), tolerance: 4, selected: false))
    #expect(a.contains(CGPoint(x: 50, y: 50), tolerance: 4, selected: true))
    #expect(!a.contains(CGPoint(x: 120, y: 50), tolerance: 4, selected: true))
}

@Test func pixelateAndTextCatchTheirWholeBox() {
    let p = Annotation(kind: .pixelate, start: .zero, end: CGPoint(x: 40, y: 40), size: 0)
    #expect(p.contains(CGPoint(x: 20, y: 20), tolerance: 0, selected: false))
    let t = Annotation(kind: .text, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 100, y: 100), size: 20, text: "Hello")
    #expect(t.contains(CGPoint(x: 110, y: 110), tolerance: 0, selected: false))
    #expect(!t.contains(CGPoint(x: 90, y: 110), tolerance: 0, selected: false))
}

@Test func rectangleHandlesSitOnCornersAndEdges() {
    let handles = Dictionary(uniqueKeysWithValues: rectangle(CGRect(x: 0, y: 0, width: 100, height: 50)).handles)
    #expect(handles.count == 8)
    #expect(handles[.handle(.topLeft)] == CGPoint(x: 0, y: 0))
    #expect(handles[.handle(.right)] == CGPoint(x: 100, y: 25))
    #expect(handles[.handle(.bottom)] == CGPoint(x: 50, y: 50))
}

@Test func arrowHasTwoEndHandlesAndTextNone() {
    let a = Annotation(kind: .arrow, start: CGPoint(x: 1, y: 2), end: CGPoint(x: 3, y: 4), size: 4)
    #expect(a.handles.map(\.0) == [.start, .end])
    let t = Annotation(kind: .text, start: .zero, end: .zero, size: 20, text: "x")
    #expect(t.handles.isEmpty)
}

@Test func draggingAnAnnotationHandleResizesAndFlips() {
    let a = rectangle(CGRect(x: 100, y: 100, width: 200, height: 100))
    let wider = a.dragging(.handle(.right), to: CGPoint(x: 400, y: 999), constrained: false)
    #expect(wider.rect == CGRect(x: 100, y: 100, width: 300, height: 100))
    let flipped = a.dragging(.handle(.right), to: CGPoint(x: 40, y: 0), constrained: false)
    #expect(flipped.rect == CGRect(x: 40, y: 100, width: 60, height: 100))
    #expect(flipped.start == CGPoint(x: 40, y: 100))
}

@Test func shiftSquaresRectanglesFromTheOppositeCorner() {
    let a = rectangle(CGRect(x: 100, y: 100, width: 200, height: 100))
    let square = a.dragging(.handle(.bottomRight), to: CGPoint(x: 250, y: 400), constrained: true)
    #expect(square.rect == CGRect(x: 100, y: 100, width: 300, height: 300))
    let drawn = Annotation(kind: .pixelate, start: .zero, end: .zero, size: 0)
        .dragging(.end, to: CGPoint(x: -30, y: 10), constrained: true)
    #expect(drawn.rect == CGRect(x: -30, y: 0, width: 30, height: 30))
}

@Test func shiftSnapsArrowsTo45Degrees() {
    let a = Annotation(kind: .arrow, start: .zero, end: CGPoint(x: 10, y: 0), size: 4)
    let snapped = a.dragging(.end, to: CGPoint(x: 100, y: 10), constrained: true)
    #expect(abs(snapped.end.y) < 0.001)
    #expect(abs(snapped.end.x - hypot(100, 10)) < 0.001)
    let diagonal = a.dragging(.end, to: CGPoint(x: 50, y: 45), constrained: true)
    #expect(abs(diagonal.end.x - diagonal.end.y) < 0.001)
}

@Test func movedShiftsBothEnds() {
    let a = Annotation(kind: .arrow, start: CGPoint(x: 1, y: 2), end: CGPoint(x: 3, y: 4), size: 4).moved(dx: 10, dy: -2)
    #expect(a.start == CGPoint(x: 11, y: 0))
    #expect(a.end == CGPoint(x: 13, y: 2))
}

@Test func clicksAndEmptyTextAreNegligible() {
    #expect(Annotation(kind: .arrow, start: .zero, end: CGPoint(x: 2, y: 2), size: 4).isNegligible)
    #expect(!Annotation(kind: .arrow, start: .zero, end: CGPoint(x: 20, y: 2), size: 4).isNegligible)
    #expect(rectangle(CGRect(x: 0, y: 0, width: 50, height: 1)).isNegligible)
    #expect(Annotation(kind: .text, start: .zero, end: .zero, size: 20, text: " \n").isNegligible)
}

@Test func arrowHeadEndsExactlyAtTheHeadAndShrinksForShortArrows() {
    let long = ArrowShape.path(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 0), width: 8)
    #expect(long.boundingBoxOfPath.maxX == 200)
    #expect(long.boundingBoxOfPath.minX == 0)
    // A 6 px arrow can't have a 28 px head; it is never longer than the arrow.
    let short = ArrowShape.path(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 6, y: 0), width: 8)
    #expect(short.boundingBoxOfPath.width <= 6.001)
    #expect(ArrowShape.path(from: .zero, to: .zero, width: 8).isEmpty)
}

@Test func textBoxGrowsWithLinesAndNeverCollapses() {
    let one = TextLayout.size(of: "Hello", fontSize: 20)
    let two = TextLayout.size(of: "Hello\nHello", fontSize: 20)
    #expect(one.width > 20)
    #expect(two.width == one.width)
    #expect(two.height == 2 * one.height)
    #expect(TextLayout.size(of: "", fontSize: 20).width == 10)
}
