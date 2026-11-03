import Carbon.HIToolbox
import Foundation

/// A global hotkey as Carbon registers it: a virtual key code plus Carbon modifier
/// flags. `key` is the label recorded when it was typed, so a non-US layout shows its
/// own character rather than the US key printed at that position.
public struct Shortcut: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    /// Carbon flags: `cmdKey`, `shiftKey`, `optionKey`, `controlKey`.
    public var modifiers: UInt32
    public var key: String

    public init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    public static let captureArea = Shortcut(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | shiftKey), key: "2")
    public static let captureFullScreen = Shortcut(
        keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(cmdKey | shiftKey), key: "1"
    )

    /// "⌃⌥⇧⌘2" — modifiers in the order macOS menus print them.
    public var displayString: String {
        var symbols = ""
        if modifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols + key
    }

    /// Carbon flags from `NSEvent.ModifierFlags.rawValue`; Core takes the raw value so
    /// it stays free of AppKit.
    public static func carbonModifiers(fromCocoa raw: UInt) -> UInt32 {
        var flags: UInt32 = 0
        if raw & (1 << 20) != 0 { flags |= UInt32(cmdKey) }
        if raw & (1 << 19) != 0 { flags |= UInt32(optionKey) }
        if raw & (1 << 18) != 0 { flags |= UInt32(controlKey) }
        if raw & (1 << 17) != 0 { flags |= UInt32(shiftKey) }
        return flags
    }

    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    private static let namedKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]

    /// The label for keys whose typed character is invisible or misleading, else nil
    /// (use the typed character).
    public static func label(forKeyCode keyCode: UInt32) -> String? {
        functionKeys[Int(keyCode)] ?? namedKeys[Int(keyCode)]
    }

    public var isFunctionKey: Bool { Self.functionKeys[Int(keyCode)] != nil }

    public enum Problem: Equatable, Sendable {
        /// One modifier isn't enough for a global shortcut: ⌘X belongs to every app,
        /// ⌥X types accented letters, ⌃X moves the cursor in text fields.
        case needsTwoModifiers
        case reservedBySystem(String)
        case duplicate(of: String)

        public var message: String {
            switch self {
            case .needsTwoModifiers: "Use at least two modifier keys, for example ⌘⇧ or ⌃⌥, or a function key."
            case .reservedBySystem(let owner): "macOS uses this for \(owner)."
            case .duplicate(let other): "Already used for \(other)."
            }
        }
    }

    private static let reserved: [Shortcut: String] = [
        Shortcut(keyCode: UInt32(kVK_ANSI_3), modifiers: UInt32(cmdKey | shiftKey), key: "3"): "screenshots",
        Shortcut(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(cmdKey | shiftKey), key: "4"): "screenshots",
        Shortcut(keyCode: UInt32(kVK_ANSI_5), modifiers: UInt32(cmdKey | shiftKey), key: "5"): "screenshots",
        Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey), key: "Space"): "Spotlight",
        Shortcut(keyCode: UInt32(kVK_Tab), modifiers: UInt32(cmdKey), key: "⇥"): "switching apps",
    ]

    /// Why this can't be a global shortcut, or nil if it can. `others` maps the names of
    /// the other actions to their shortcuts.
    public func problem(among others: [String: Shortcut]) -> Problem? {
        if let owner = Self.reserved.first(where: { $0.key.matches(self) })?.value {
            return .reservedBySystem(owner)
        }
        if let other = others.first(where: { $0.value.matches(self) })?.key {
            return .duplicate(of: other)
        }
        let count = [cmdKey, optionKey, controlKey, shiftKey].filter { modifiers & UInt32($0) != 0 }.count
        let hasNonShift = modifiers & UInt32(cmdKey | optionKey | controlKey) != 0
        if !isFunctionKey, count < 2 || !hasNonShift { return .needsTwoModifiers }
        return nil
    }

    /// Same keystroke, whatever label each was recorded with.
    public func matches(_ other: Shortcut) -> Bool {
        keyCode == other.keyCode && modifiers == other.modifiers
    }
}
