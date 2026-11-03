import AppKit
import ScreenshottCore

/// What the Settings window changes, kept in UserDefaults. Shortcuts live in
/// ShortcutCenter, which also has to register them.
@MainActor
final class Preferences: ObservableObject {
    static let defaultSaveDirectory = FileManager.default
        .urls(for: .picturesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Screenshott")

    private let defaults: UserDefaults

    @Published var saveDirectory: URL {
        didSet { defaults.set(saveDirectory.path, forKey: Key.saveDirectory) }
    }
    @Published var copyToClipboard: Bool {
        didSet { defaults.set(copyToClipboard, forKey: Key.copyToClipboard) }
    }
    @Published var showThumbnail: Bool {
        didSet { defaults.set(showThumbnail, forKey: Key.showThumbnail) }
    }
    @Published var playSound: Bool {
        didSet { defaults.set(playSound, forKey: Key.playSound) }
    }
    /// Off: a 2x capture is saved at its 1x size (decision 4b's opt-out).
    @Published var keepRetinaResolution: Bool {
        didSet { defaults.set(keepRetinaResolution, forKey: Key.keepRetinaResolution) }
    }

    private enum Key {
        static let saveDirectory = "saveDirectory"
        static let copyToClipboard = "copyToClipboard"
        static let showThumbnail = "showThumbnail"
        static let playSound = "playSound"
        static let keepRetinaResolution = "keepRetinaResolution"
        static let shortcutPrefix = "shortcut."
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.copyToClipboard: true, Key.showThumbnail: true, Key.playSound: true, Key.keepRetinaResolution: true,
        ])
        saveDirectory = defaults.string(forKey: Key.saveDirectory).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? Self.defaultSaveDirectory
        copyToClipboard = defaults.bool(forKey: Key.copyToClipboard)
        showThumbnail = defaults.bool(forKey: Key.showThumbnail)
        playSound = defaults.bool(forKey: Key.playSound)
        keepRetinaResolution = defaults.bool(forKey: Key.keepRetinaResolution)
    }

    // MARK: - Shortcuts

    /// `.some(nil)` means the user cleared it; nil means never set, so the default holds.
    func storedShortcut(_ name: String) -> Shortcut?? {
        guard let data = defaults.data(forKey: Key.shortcutPrefix + name) else { return nil }
        if data.isEmpty { return .some(nil) }
        return .some(try? JSONDecoder().decode(Shortcut.self, from: data))
    }

    func storeShortcut(_ shortcut: Shortcut?, _ name: String) {
        let data = shortcut.flatMap { try? JSONEncoder().encode($0) } ?? Data()
        defaults.set(data, forKey: Key.shortcutPrefix + name)
    }
}
