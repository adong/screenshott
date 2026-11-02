import CoreGraphics
import Testing
@testable import ScreenshottCore

// Laptop at the origin, external display to its right and raised (Cocoa coordinates).
private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
private let external = CGRect(x: 1512, y: 200, width: 2560, height: 1440)
private let frames = [laptop, external]

@Test func picksDisplayContainingPoint() {
    #expect(DisplayPicking.index(containing: CGPoint(x: 100, y: 100), in: frames) == 0)
    #expect(DisplayPicking.index(containing: CGPoint(x: 2000, y: 900), in: frames) == 1)
}

@Test func sharedEdgeBelongsToTheDisplayOnTheRight() {
    #expect(DisplayPicking.index(containing: CGPoint(x: 1512, y: 500), in: frames) == 1)
}

@Test func cursorOnTopEdgeStillPicksThatDisplay() {
    // NSEvent.mouseLocation reports y == maxY when the cursor is pushed against the top.
    #expect(DisplayPicking.index(containing: CGPoint(x: 100, y: 982), in: frames) == 0)
}

@Test func pointOutsideEveryDisplayPicksNothing() {
    #expect(DisplayPicking.index(containing: CGPoint(x: 100, y: 1500), in: frames) == nil)
}
