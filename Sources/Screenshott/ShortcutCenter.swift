import AppKit
import Carbon.HIToolbox
import ScreenshottCore

/// The app's global shortcuts: which action each one runs, what it is bound to, and
/// whether macOS let us have it. Settings changes them through `set(_:for:)`.
@MainActor
final class ShortcutCenter: ObservableObject {
    enum Action: UInt32, CaseIterable, Identifiable {
        case captureArea = 1
        case captureFullScreen = 2

        var id: UInt32 { rawValue }

        var title: String {
            switch self {
            case .captureArea: "Capture Area"
            case .captureFullScreen: "Capture Full Screen"
            }
        }

        var defaultShortcut: Shortcut {
            switch self {
            case .captureArea: .captureArea
            case .captureFullScreen: .captureFullScreen
            }
        }

        /// Stable name for UserDefaults.
        var storageName: String {
            switch self {
            case .captureArea: "captureArea"
            case .captureFullScreen: "captureFullScreen"
            }
        }
    }

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
            let shortcut = preferences.storedShortcut(action.storageName) ?? action.defaultShortcut
            bind(action, to: shortcut)
        }
    }

    /// Rebinds `action`; nil clears it. Returns why it was refused, or nil. A refused
    /// shortcut leaves the old one in place.
    func set(_ shortcut: Shortcut?, for action: Action) -> String? {
        if let shortcut {
            var others: [String: Shortcut] = [:]
            for (other, bound) in shortcuts where other != action { others[other.title] = bound }
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
        let status = HotKeys.bind(action.rawValue, to: shortcut) { [weak self] in self?.handlers[action]?() }
        shortcuts[action] = shortcut
        if status == noErr { taken.remove(action) } else { taken.insert(action) }
        return status == noErr
    }
}
