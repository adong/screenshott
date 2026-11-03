import Carbon.HIToolbox
import CoreGraphics
import Testing
@testable import ScreenshottCore

@Test func theSevenPresetsOfTheTableShip() {
    #expect(PresetID.allCases.count == 7)
    #expect(PresetID.allCases.map(\.preset.title) == [
        "Capture Area", "Capture Full Screen", "Full Screen to Editor", "Scrolling Capture",
        "Live Area", "Repeat Last Area", "Delayed Area",
    ])
}

@Test func shortcutsStoredBeforePresetsStillLoad() {
    // UserDefaults keys "shortcut.captureArea" / "shortcut.captureFullScreen" and Carbon
    // slots 1 / 2 predate presets.
    #expect(PresetID(rawValue: "captureArea") == .captureArea)
    #expect(PresetID(rawValue: "captureFullScreen") == .captureFullScreen)
    #expect(PresetID.captureArea.hotKeyID == 1)
    #expect(PresetID.captureFullScreen.hotKeyID == 2)
}

@Test func hotKeySlotsAreUnique() {
    let ids = PresetID.allCases.map(\.hotKeyID)
    #expect(Set(ids).count == ids.count)
}

@Test func defaultHotkeysFollowTheTable() {
    let shortcuts = PresetID.allCases.map { $0.preset.defaultShortcut?.displayString }
    #expect(shortcuts == ["⇧⌘2", "⇧⌘1", "⌥⇧⌘1", "⌥⇧⌘2", nil, nil, nil])
}

@Test func defaultHotkeysAreValidTogether() {
    let bound = PresetID.allCases.compactMap { id in id.preset.defaultShortcut.map { (id, $0) } }
    for (id, shortcut) in bound {
        var others: [String: Shortcut] = [:]
        for (other, s) in bound where other != id { others[other.preset.title] = s }
        #expect(shortcut.problem(among: others) == nil)
    }
}

@Test func presetsDescribeScreenSelectionAndAction() {
    let area = PresetID.captureArea.preset
    #expect(area.screen == .frozen && area.selection == .area && area.defaultAction == .standard)
    let editor = PresetID.fullScreenToEditor.preset
    #expect(editor.selection == .none && editor.defaultAction == .openEditor)
    #expect(PresetID.liveArea.preset.screen == .live)
    #expect(PresetID.repeatArea.preset.selection == .lastArea)
    #expect(PresetID.delayedArea.preset.delay == 3)
    #expect(PresetID.captureArea.preset.delay == 0)
}

@Test func storedActionWinsWhenKnown() {
    let area = PresetID.captureArea.preset
    #expect(area.action(stored: nil) == .standard)
    #expect(area.action(stored: "copy") == .copyOnly)
    #expect(area.action(stored: "save-as") == .saveAs)
    // A name from a newer version, or garbage, falls back.
    #expect(area.action(stored: "teleport") == .standard)
}

@Test func scrollingKeepsItsOwnAction() {
    #expect(!PresetID.captureScrolling.preset.hasConfigurableAction)
    #expect(PresetID.captureScrolling.preset.action(stored: "copy") == .standard)
}

@Test func delayIsOneOfTheChoices() {
    let delayed = PresetID.delayedArea.preset
    #expect(delayed.delay(stored: nil) == 3)
    #expect(delayed.delay(stored: 10) == 10)
    #expect(delayed.delay(stored: 7) == 3)
    // Presets without a countdown ignore a stored one.
    #expect(PresetID.captureArea.preset.delay(stored: 5) == 0)
}

@Test func actionNamesRoundTrip() {
    for action in CaptureAction.presetChoices + [.save, .thumbnail] {
        #expect(CaptureAction(name: action.name) == action)
    }
    #expect(CaptureAction(name: "") == nil)
}

private let retina = OverlayGeometry(
    pointSize: CGSize(width: 1512, height: 982), pixelSize: PixelSize(width: 3024, height: 1964)
)

@Test func viewRectMapsBackToTheSamePixels() {
    let pixels = PixelRect(x: 200, y: 564, width: 400, height: 401)
    #expect(retina.pixelRect(forView: retina.viewRect(for: pixels)) == pixels)
}

@Test func rememberedAreaIsCutToTheDisplay() {
    // A remembered area that now hangs off a smaller display keeps only the part on it.
    let rect = retina.pixelRect(forView: CGRect(x: 1400, y: -50, width: 300, height: 100))
    #expect(rect == PixelRect(x: 2800, y: 1864, width: 224, height: 100))
    #expect(retina.pixelRect(forView: CGRect(x: 2000, y: 0, width: 10, height: 10)) == nil)
}

@Test func windowBoundsFlipIntoCocoaCoordinates() {
    // A 400 × 300 window 100 pt below the top of a 982 pt main screen.
    let cocoa = GlobalCoordinates.cocoaRect(
        fromCG: CGRect(x: 50, y: 100, width: 400, height: 300), mainScreenHeight: 982
    )
    #expect(cocoa == CGRect(x: 50, y: 582, width: 400, height: 300))
}
