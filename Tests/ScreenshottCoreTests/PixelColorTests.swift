import CoreGraphics
import Testing
@testable import ScreenshottCore

@Test func readsThePixelUnderAPointAsHex() throws {
    // patternImage: red = x, green = y, blue = 255 where x + y is even.
    let image = patternImage(width: 40, height: 30)
    #expect(PixelColor.at(PixelPoint(x: 10, y: 20), in: image)?.hex == "#0A14FF")
    #expect(PixelColor.at(PixelPoint(x: 11, y: 20), in: image)?.hex == "#0B1400")
    #expect(PixelColor.at(PixelPoint(x: 0, y: 0), in: image) == PixelColor(red: 0, green: 0, blue: 255))
}

@Test func outsideTheImageThereIsNoColor() {
    let image = patternImage(width: 4, height: 4)
    #expect(PixelColor.at(PixelPoint(x: 4, y: 0), in: image) == nil)
    #expect(PixelColor.at(PixelPoint(x: 0, y: -1), in: image) == nil)
}

@Test func hexIsTwoUppercaseDigitsPerChannel() {
    #expect(PixelColor(red: 255, green: 0, blue: 171).hex == "#FF00AB")
}
