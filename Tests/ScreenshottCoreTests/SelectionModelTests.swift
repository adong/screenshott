import Testing
@testable import ScreenshottCore

private func model(selection: PixelRect? = nil) -> SelectionModel {
    var m = SelectionModel(bounds: PixelSize(width: 1000, height: 800), clickSlop: 3)
    m.selection = selection
    return m
}

private let box = PixelRect(x: 100, y: 100, width: 200, height: 100)

@Test func dragOutsideDrawsANewSelectionThatStaysAfterMouseUp() {
    var m = model()
    #expect(m.begin(at: PixelPoint(x: 300, y: 200), tolerance: 6) == .outside)
    m.drag(to: PixelPoint(x: 120, y: 260))
    #expect(m.end() == false)
    #expect(m.selection == PixelRect(x: 120, y: 200, width: 180, height: 60))
}

@Test func pressInsideTheSlopIsAClickAndChangesNothing() {
    var m = model(selection: box)
    m.begin(at: PixelPoint(x: 600, y: 600), tolerance: 6)
    m.drag(to: PixelPoint(x: 603, y: 598))
    #expect(m.end() == true)
    #expect(m.selection == box)
}

@Test func dragInsideMovesTheSelection() {
    var m = model(selection: box)
    #expect(m.begin(at: PixelPoint(x: 200, y: 150), tolerance: 6) == .inside)
    m.drag(to: PixelPoint(x: 250, y: 130))
    #expect(m.isMoving)
    #expect(m.end() == false)
    #expect(m.selection == PixelRect(x: 150, y: 80, width: 200, height: 100))
}

@Test func movingStopsAtTheImageEdge() {
    var m = model(selection: box)
    m.begin(at: PixelPoint(x: 200, y: 150), tolerance: 6)
    m.drag(to: PixelPoint(x: -500, y: 5000))
    #expect(m.selection == PixelRect(x: 0, y: 700, width: 200, height: 100))
}

@Test func edgesAndCornersAreHandles() {
    let m = model(selection: box)
    #expect(m.hit(PixelPoint(x: 100, y: 100), tolerance: 6) == .handle(.topLeft))
    #expect(m.hit(PixelPoint(x: 305, y: 204), tolerance: 6) == .handle(.bottomRight))
    #expect(m.hit(PixelPoint(x: 200, y: 96), tolerance: 6) == .handle(.top))
    #expect(m.hit(PixelPoint(x: 94, y: 150), tolerance: 6) == .handle(.left))
    #expect(m.hit(PixelPoint(x: 200, y: 150), tolerance: 6) == .inside)
    #expect(m.hit(PixelPoint(x: 200, y: 93), tolerance: 6) == .outside)
}

@Test func thinSelectionPicksTheNearerEdge() {
    let m = model(selection: PixelRect(x: 100, y: 100, width: 4, height: 200))
    #expect(m.hit(PixelPoint(x: 101, y: 150), tolerance: 6) == .handle(.left))
    #expect(m.hit(PixelPoint(x: 103, y: 150), tolerance: 6) == .handle(.right))
}

@Test func draggingAHandleResizesAndFlipsPastTheOppositeEdge() {
    var m = model(selection: box)
    m.begin(at: PixelPoint(x: 300, y: 150), tolerance: 6)  // right edge
    m.drag(to: PixelPoint(x: 400, y: 170))
    #expect(m.selection == PixelRect(x: 100, y: 100, width: 300, height: 100))
    m.drag(to: PixelPoint(x: 40, y: 170))
    #expect(m.selection == PixelRect(x: 40, y: 100, width: 60, height: 100))
}

@Test func cornerHandleMovesTwoEdges() {
    var m = model(selection: box)
    m.begin(at: PixelPoint(x: 100, y: 100), tolerance: 6)
    m.drag(to: PixelPoint(x: 90, y: 50))
    #expect(m.selection == PixelRect(x: 90, y: 50, width: 210, height: 150))
}

@Test func nudgeMovesAndStopsAtEdges() {
    var m = model(selection: box)
    m.nudge(dx: 1, dy: -10)
    #expect(m.selection == PixelRect(x: 101, y: 90, width: 200, height: 100))
    m.nudge(dx: 5000, dy: 0)
    #expect(m.selection?.maxX == 1000)
}

@Test func resizeKeepsAtLeastOnePixelAndStaysInside() {
    var m = model(selection: box)
    m.resize(dx: -500, dy: 10)
    #expect(m.selection == PixelRect(x: 100, y: 100, width: 1, height: 110))
    m.resize(dx: 5000, dy: 5000)
    #expect(m.selection == PixelRect(x: 100, y: 100, width: 900, height: 700))
}

@Test func nudgeWithoutASelectionDoesNothing() {
    var m = model()
    m.nudge(dx: 1, dy: 1)
    m.resize(dx: 1, dy: 1)
    #expect(m.selection == nil)
}

@Test func endWithoutBeginIsNotAClick() {
    var m = model()
    #expect(m.end() == false)
}

// MARK: - Hold Space to move

@Test func holdingSpaceWhileDrawingMovesTheRectangleAtItsSize() {
    var m = model()
    m.begin(at: PixelPoint(x: 100, y: 100), tolerance: 6)
    m.drag(to: PixelPoint(x: 300, y: 200))
    m.holdToMove(true)
    #expect(m.isMoving)
    m.drag(to: PixelPoint(x: 350, y: 260))
    #expect(m.selection == PixelRect(x: 150, y: 160, width: 200, height: 100))
}

@Test func lettingGoOfSpaceGoesBackToDrawingFromTheMovedCorner() {
    var m = model()
    m.begin(at: PixelPoint(x: 100, y: 100), tolerance: 6)
    m.drag(to: PixelPoint(x: 300, y: 200))
    m.holdToMove(true)
    m.drag(to: PixelPoint(x: 350, y: 260))
    m.holdToMove(false)
    #expect(!m.isMoving)
    // The anchor moved with the rectangle, so the pointer resizes from (150, 160).
    m.drag(to: PixelPoint(x: 400, y: 300))
    #expect(m.end() == false)
    #expect(m.selection == PixelRect(x: 150, y: 160, width: 250, height: 140))
}

@Test func aMovedRectangleStopsAtTheImageEdgeAndDrawsOnFromThere() {
    var m = model()
    m.begin(at: PixelPoint(x: 100, y: 100), tolerance: 6)
    m.drag(to: PixelPoint(x: 300, y: 200))
    m.holdToMove(true)
    m.drag(to: PixelPoint(x: -500, y: 5000))
    #expect(m.selection == PixelRect(x: 0, y: 700, width: 200, height: 100))
    m.holdToMove(false)
    // The anchor is the moved rectangle's top-left corner, not off the image.
    m.drag(to: PixelPoint(x: 50, y: 750))
    #expect(m.selection == PixelRect(x: 0, y: 700, width: 50, height: 50))
}

@Test func holdingSpaceWhileResizingMovesAndThenResizesAgain() {
    var m = model(selection: box)
    #expect(m.begin(at: PixelPoint(x: 300, y: 200), tolerance: 6) == .handle(.bottomRight))
    m.drag(to: PixelPoint(x: 400, y: 300))
    #expect(m.selection == PixelRect(x: 100, y: 100, width: 300, height: 200))
    m.holdToMove(true)
    m.drag(to: PixelPoint(x: 450, y: 320))
    #expect(m.selection == PixelRect(x: 150, y: 120, width: 300, height: 200))
    m.holdToMove(false)
    m.drag(to: PixelPoint(x: 500, y: 320))
    #expect(m.selection == PixelRect(x: 150, y: 120, width: 350, height: 200))
}

@Test func spaceDoesNothingBeforeTheDragLeavesTheSlopOrWithoutADrag() {
    var m = model(selection: box)
    m.holdToMove(true)
    #expect(!m.isMoving)
    m.begin(at: PixelPoint(x: 600, y: 600), tolerance: 6)
    m.holdToMove(true)
    m.drag(to: PixelPoint(x: 700, y: 650))
    // Still drawing: Space went down while the press was a click.
    #expect(m.selection == PixelRect(x: 600, y: 600, width: 100, height: 50))
    #expect(!m.isMoving)
}

@Test func mouseUpWhileHoldingSpaceKeepsTheMovedRectangle() {
    var m = model()
    m.begin(at: PixelPoint(x: 100, y: 100), tolerance: 6)
    m.drag(to: PixelPoint(x: 300, y: 200))
    m.holdToMove(true)
    m.drag(to: PixelPoint(x: 310, y: 210))
    #expect(m.end() == false)
    #expect(!m.isMoving)
    #expect(m.selection == PixelRect(x: 110, y: 110, width: 200, height: 100))
    // Space coming up after the press ended changes nothing.
    m.holdToMove(false)
    #expect(m.selection == PixelRect(x: 110, y: 110, width: 200, height: 100))
}
