import Carbon.HIToolbox
import Foundation
import Testing
@testable import ScreenshottCore

private func shortcut(_ keyCode: Int, _ modifiers: Int, _ key: String = "X") -> Shortcut {
    Shortcut(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers), key: key)
}

@Test func displayStringUsesMenuModifierOrder() {
    #expect(shortcut(kVK_ANSI_2, cmdKey | shiftKey | optionKey | controlKey, "2").displayString == "⌃⌥⇧⌘2")
    #expect(Shortcut.captureArea.displayString == "⇧⌘2")
}

@Test func cocoaFlagsConvertToCarbon() {
    let command: UInt = 1 << 20, option: UInt = 1 << 19, control: UInt = 1 << 18, shift: UInt = 1 << 17
    #expect(Shortcut.carbonModifiers(fromCocoa: command | shift) == UInt32(cmdKey | shiftKey))
    #expect(Shortcut.carbonModifiers(fromCocoa: option | control) == UInt32(optionKey | controlKey))
    // Caps Lock and the device-dependent bits are ignored.
    #expect(Shortcut.carbonModifiers(fromCocoa: (1 << 16) | 0x100) == 0)
}

@Test func defaultsAreValid() {
    #expect(Shortcut.captureArea.problem(among: ["Capture Full Screen": .captureFullScreen]) == nil)
    #expect(Shortcut.captureFullScreen.problem(among: ["Capture Area": .captureArea]) == nil)
}

@Test func oneModifierIsNotEnough() {
    #expect(shortcut(kVK_ANSI_S, cmdKey).problem(among: [:]) == .needsTwoModifiers)
    #expect(shortcut(kVK_ANSI_S, optionKey).problem(among: [:]) == .needsTwoModifiers)
    #expect(shortcut(kVK_ANSI_S, 0).problem(among: [:]) == .needsTwoModifiers)
}

@Test func shiftDoesNotCountAsTheSecondRealModifier() {
    #expect(shortcut(kVK_ANSI_S, shiftKey).problem(among: [:]) == .needsTwoModifiers)
    #expect(shortcut(kVK_ANSI_S, controlKey | optionKey).problem(among: [:]) == nil)
}

@Test func functionKeysWorkAlone() {
    #expect(shortcut(kVK_F5, 0, "F5").problem(among: [:]) == nil)
    #expect(shortcut(kVK_F5, 0, "F5").isFunctionKey)
}

@Test func systemScreenshotKeysAreReserved() {
    #expect(shortcut(kVK_ANSI_4, cmdKey | shiftKey, "4").problem(among: [:]) == .reservedBySystem("screenshots"))
    #expect(shortcut(kVK_Space, cmdKey, "Space").problem(among: [:]) == .reservedBySystem("Spotlight"))
}

@Test func duplicatesAreCaughtWhateverTheLabel() {
    let typedOnAnotherLayout = shortcut(kVK_ANSI_2, cmdKey | shiftKey, "é")
    #expect(typedOnAnotherLayout.problem(among: ["Capture Area": .captureArea]) == .duplicate(of: "Capture Area"))
}

@Test func specialKeysGetLabels() {
    #expect(Shortcut.label(forKeyCode: UInt32(kVK_F12)) == "F12")
    #expect(Shortcut.label(forKeyCode: UInt32(kVK_Space)) == "Space")
    #expect(Shortcut.label(forKeyCode: UInt32(kVK_ANSI_A)) == nil)
}

@Test func roundTripsThroughJSON() throws {
    let original = shortcut(kVK_ANSI_7, controlKey | optionKey, "7")
    let decoded = try JSONDecoder().decode(Shortcut.self, from: JSONEncoder().encode(original))
    #expect(decoded == original)
}
