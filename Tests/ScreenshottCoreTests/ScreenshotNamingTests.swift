import Foundation
import Testing
@testable import ScreenshottCore

private let utc = TimeZone(identifier: "UTC")!

private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    return calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
}

@Test func fileNameIsSortableAndColonFree() {
    let name = ScreenshotNaming.fileName(for: date(2026, 11, 1, 17, 47, 3), timeZone: utc)
    #expect(name == "Screenshott 2026-11-01 at 17.47.03.png")
    #expect(!name.contains(":"))
}

@Test func fileNameUsesTwentyFourHourClock() {
    let name = ScreenshotNaming.fileName(for: date(2026, 11, 1, 0, 5, 9), timeZone: utc)
    #expect(name == "Screenshott 2026-11-01 at 00.05.09.png")
}

@Test func uniqueURLReturnsPlainNameWhenFree() {
    let dir = URL(fileURLWithPath: "/shots")
    let url = ScreenshotNaming.uniqueURL(in: dir, fileName: "a.png") { _ in false }
    #expect(url.lastPathComponent == "a.png")
}

@Test func uniqueURLSkipsTakenSuffixes() {
    let dir = URL(fileURLWithPath: "/shots")
    let taken: Set<String> = ["a.png", "a (2).png"]
    let url = ScreenshotNaming.uniqueURL(in: dir, fileName: "a.png") { taken.contains($0.lastPathComponent) }
    #expect(url.lastPathComponent == "a (3).png")
}
