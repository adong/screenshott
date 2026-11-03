import CoreGraphics
import Testing
@testable import ScreenshottCore

// A 1512 × 982 pt Retina laptop screen and its 3024 × 1964 px frozen image.
private let retina = OverlayGeometry(
    pointSize: CGSize(width: 1512, height: 982), pixelSize: PixelSize(width: 3024, height: 1964)
)
private let external = OverlayGeometry(
    pointSize: CGSize(width: 2560, height: 1440), pixelSize: PixelSize(width: 2560, height: 1440)
)

@Test func scaleComesFromTheImage() {
    #expect(retina.scale == 2)
    #expect(external.scale == 1)
}

@Test func pixelFlipsYToATopLeftOrigin() {
    // The view's top-left point is the image's first pixel.
    #expect(retina.pixel(at: CGPoint(x: 0, y: 982)) == PixelPoint(x: 0, y: 0))
    #expect(retina.pixel(at: CGPoint(x: 10.25, y: 972)) == PixelPoint(x: 20, y: 20))
    // Half a point is one Retina pixel.
    #expect(retina.pixel(at: CGPoint(x: 10.5, y: 972)) == PixelPoint(x: 21, y: 20))
}

@Test func pixelClampsToTheLastRowAndColumn() {
    #expect(retina.pixel(at: CGPoint(x: 1512, y: 0)) == PixelPoint(x: 3023, y: 1963))
    #expect(retina.pixel(at: CGPoint(x: -5, y: 2000)) == PixelPoint(x: 0, y: 0))
}

@Test func edgeRoundsToTheNearestGridLineAndReachesTheFarSide() {
    #expect(external.edge(at: CGPoint(x: 10.4, y: 1429.6)) == PixelPoint(x: 10, y: 10))
    #expect(external.edge(at: CGPoint(x: 2560, y: 0)) == PixelPoint(x: 2560, y: 1440))
    #expect(external.edge(at: CGPoint(x: 3000, y: -40)) == PixelPoint(x: 2560, y: 1440))
}

@Test func viewRectIsTheInverseOfEdges() {
    let rect = PixelRect(corner: retina.edge(at: CGPoint(x: 100, y: 700)), retina.edge(at: CGPoint(x: 300, y: 500)))
    #expect(rect == PixelRect(x: 200, y: 564, width: 400, height: 400))
    #expect(retina.viewRect(for: rect) == CGRect(x: 100, y: 500, width: 200, height: 200))
}

@Test func windowRectMapsFromGlobalCoordinatesToThisDisplay() {
    // External display sits right of the laptop in CG global space.
    let bounds = CGRect(x: 1512, y: -200, width: 2560, height: 1440)
    let window = CGRect(x: 1612, y: -100, width: 800, height: 600)
    #expect(external.pixelRect(forGlobal: window, displayBounds: bounds)
        == PixelRect(x: 100, y: 100, width: 800, height: 600))
}

@Test func windowRectIsCutToTheDisplayAndScaled() {
    let bounds = CGRect(x: 0, y: 0, width: 1512, height: 982)
    // Hangs off the left and bottom of the laptop screen.
    let window = CGRect(x: -100, y: 900, width: 400, height: 300)
    #expect(retina.pixelRect(forGlobal: window, displayBounds: bounds)
        == PixelRect(x: 0, y: 1800, width: 600, height: 164))
}

@Test func windowOnAnotherDisplayMapsToNothing() {
    let bounds = CGRect(x: 0, y: 0, width: 1512, height: 982)
    #expect(retina.pixelRect(forGlobal: CGRect(x: 2000, y: 0, width: 300, height: 300), displayBounds: bounds) == nil)
}

@Test func cornerInitAcceptsEitherOrder() {
    let a = PixelPoint(x: 50, y: 10), b = PixelPoint(x: 20, y: 40)
    #expect(PixelRect(corner: a, b) == PixelRect(x: 20, y: 10, width: 30, height: 30))
    #expect(PixelRect(corner: b, a) == PixelRect(corner: a, b))
}

@Test func containsIsHalfOpen() {
    let r = PixelRect(x: 10, y: 10, width: 5, height: 5)
    #expect(r.contains(PixelPoint(x: 10, y: 10)))
    #expect(r.contains(PixelPoint(x: 14, y: 14)))
    #expect(!r.contains(PixelPoint(x: 15, y: 14)))
}

@Test func cocoaToCoreGraphicsFlipsAroundTheMainScreen() {
    #expect(GlobalCoordinates.cgPoint(fromCocoa: CGPoint(x: 30, y: 900), mainScreenHeight: 982)
        == CGPoint(x: 30, y: 82))
}
