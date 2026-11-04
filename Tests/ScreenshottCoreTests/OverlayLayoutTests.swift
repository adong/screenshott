import CoreGraphics
import Testing
@testable import ScreenshottCore

private let image = PixelSize(width: 2560, height: 1440)

@Test func magnifierSourceIsCenteredOnTheCursor() {
    let (rect, marker) = MagnifierLayout.source(around: PixelPoint(x: 100, y: 200), in: image)
    #expect(rect == PixelRect(x: 93, y: 193, width: 15, height: 15))
    #expect(marker == PixelPoint(x: 7, y: 7))
}

@Test func magnifierSourceSlidesInsideAtTheEdges() {
    let (rect, marker) = MagnifierLayout.source(around: PixelPoint(x: 2559, y: 0), in: image)
    #expect(rect == PixelRect(x: 2545, y: 0, width: 15, height: 15))
    #expect(marker == PixelPoint(x: 14, y: 0))
}

@Test func magnifierSitsBelowRightAndFlipsAtEdges() {
    let size = CGSize(width: 135, height: 155), screen = CGSize(width: 1512, height: 982)
    #expect(MagnifierLayout.frame(size: size, cursor: CGPoint(x: 500, y: 500), in: screen)
        == CGRect(x: 524, y: 321, width: 135, height: 155))
    // Near the bottom-right corner it goes above and to the left.
    #expect(MagnifierLayout.frame(size: size, cursor: CGPoint(x: 1500, y: 20), in: screen)
        == CGRect(x: 1341, y: 44, width: 135, height: 155))
}

@Test func thumbnailFitsTheBoxWithoutEnlarging() {
    // 2560 × 1440 px at 2x is 1280 × 720 pt, fit into 240 × 160.
    #expect(ThumbnailLayout.size(for: PixelSize(width: 2560, height: 1440), scale: 2)
        == CGSize(width: 240, height: 135))
    #expect(ThumbnailLayout.size(for: PixelSize(width: 100, height: 80), scale: 1)
        == CGSize(width: 100, height: 80))
}

@Test func thumbnailHasAMinimumSide() {
    #expect(ThumbnailLayout.size(for: PixelSize(width: 2000, height: 4), scale: 1)
        == CGSize(width: 240, height: 56))
}

@Test func thumbnailsStackUpFromTheBottomRight() {
    let visible = CGRect(x: 0, y: 70, width: 1512, height: 880)
    let frames = ThumbnailLayout.frames(
        sizes: [CGSize(width: 240, height: 135), CGSize(width: 100, height: 80)], in: visible
    )
    #expect(frames == [
        CGRect(x: 1256, y: 86, width: 240, height: 135),
        CGRect(x: 1396, y: 233, width: 100, height: 80),
    ])
}

@Test func tagSitsJustAboveRightOfTheCursorWhenTheLoupeIsBelow() {
    let tag = CGSize(width: 130, height: 20), screen = CGSize(width: 1512, height: 982)
    let cursor = CGPoint(x: 500, y: 500)
    let loupe = MagnifierLayout.frame(size: CGSize(width: 135, height: 135), cursor: cursor, in: screen)
    let frame = MagnifierLayout.tagFrame(size: tag, cursor: cursor, in: screen, loupe: loupe)
    #expect(frame == CGRect(x: 512, y: 512, width: 130, height: 20))
    #expect(!frame.intersects(loupe))
    // With the magnifier off it's in the same place.
    #expect(MagnifierLayout.tagFrame(size: tag, cursor: cursor, in: screen, loupe: nil) == frame)
}

@Test func tagNeverCoversTheLoupeNearTheEdges() {
    let tag = CGSize(width: 130, height: 20), screen = CGSize(width: 1512, height: 982)
    let loupeSize = CGSize(width: 135, height: 135)
    for cursor in [
        CGPoint(x: 1500, y: 20), CGPoint(x: 5, y: 975), CGPoint(x: 1505, y: 975), CGPoint(x: 5, y: 5),
        CGPoint(x: 756, y: 975), CGPoint(x: 756, y: 3),
    ] {
        let loupe = MagnifierLayout.frame(size: loupeSize, cursor: cursor, in: screen)
        let frame = MagnifierLayout.tagFrame(size: tag, cursor: cursor, in: screen, loupe: loupe)
        #expect(!frame.intersects(loupe), "cursor \(cursor)")
        #expect(CGRect(origin: .zero, size: screen).contains(frame), "cursor \(cursor)")
    }
}
