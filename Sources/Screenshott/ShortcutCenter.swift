import AppKit
import Carbon.HIToolbox
import ScreenshottCore

/// The app's global shortcuts: one per preset, what each is bound to, and whether
/// macOS let us have it. Settings changes them through `set(_:for:)`.
@MainActor
final class ShortcutCenter: ObservableObject {
    /// Hotkeys belong to presets; a workflow gets one by being a preset's Enter action.
    typealias Action = PresetID

    @Published private(set) var shortcuts: [Action: Shortcut] = [:]
    /// Bound, but registration failed — usually another app (Shottr) owns the combo.
    @Published private(set) var taken: Set<Action> = []

    private let preferences: Preferences
    private var handlers: [Action: () -> Void] = [:]

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    /// Registers every action's saved (or default) shortcut.
    func start(handlers: [Action: () -> Void]) {
        self.handlers = handlers
        for action in Action.allCases {
            let shortcut = preferences.storedShortcut(action.storageName) ?? action.preset.defaultShortcut
            bind(action, to: shortcut)
        }
    }

    /// Rebinds `action`; nil clears it. Returns why it was refused, or nil. A refused
    /// shortcut leaves the old one in place.
    func set(_ shortcut: Shortcut?, for action: Action) -> String? {
        if let shortcut {
            var others: [String: Shortcut] = [:]
            for (other, bound) in shortcuts where other != action { others[other.preset.title] = bound }
            if let problem = shortcut.problem(among: others) { return problem.message }
        }
        let previous = shortcuts[action]
        if !bind(action, to: shortcut), let shortcut {
            bind(action, to: previous)
            return "\(shortcut.displayString) is already taken by another app."
        }
        preferences.storeShortcut(shortcut, action.storageName)
        Log.write("shortcut \(action.storageName) = \(shortcut?.displayString ?? "none")")
        return nil
    }

    func statusLine() -> String {
        Action.allCases.map { action in
            let shortcut = shortcuts[action]?.displayString ?? "none"
            return "\(action.storageName)=\(shortcut)\(taken.contains(action) ? "(taken)" : "")"
        }.joined(separator: " ")
    }

    @discardableResult
    private func bind(_ action: Action, to shortcut: Shortcut?) -> Bool {
        let status = HotKeys.bind(action.hotKeyID, to: shortcut) { [weak self] in self?.handlers[action]?() }
        shortcuts[action] = shortcut
        if status == noErr { taken.remove(action) } else { taken.insert(action) }
        return status == noErr
    }
}

extension PresetID {
    var title: String { preset.title }
    var defaultShortcut: Shortcut? { preset.defaultShortcut }
    /// Stable name for UserDefaults.
    var storageName: String { rawValue }
}
