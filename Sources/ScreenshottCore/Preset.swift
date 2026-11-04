import Carbon.HIToolbox
import CoreGraphics

/// The v1 preset table (decision 6). Every hotkey triggers one of these. The raw value
/// is the UserDefaults name, so the two shortcuts stored before presets existed
/// (`captureArea`, `captureFullScreen`) still load.
public enum PresetID: String, CaseIterable, Identifiable, Sendable {
    case captureArea
    case captureFullScreen
    case fullScreenToEditor
    case captureScrolling
    case liveArea
    case repeatArea
    case delayedArea

    public var id: String { rawValue }

    /// The Carbon hotkey slot. 1 and 2 predate presets; never renumber.
    public var hotKeyID: UInt32 {
        switch self {
        case .captureArea: 1
        case .captureFullScreen: 2
        case .fullScreenToEditor: 3
        case .captureScrolling: 4
        case .liveArea: 5
        case .repeatArea: 6
        case .delayedArea: 7
        }
    }

    public var preset: Preset {
        switch self {
        case .captureArea:
            Preset(id: self, title: "Capture Area", screen: .frozen, selection: .area, defaultAction: .standard,
                   defaultShortcut: .captureArea)
        case .captureFullScreen:
            Preset(id: self, title: "Capture Full Screen", screen: .frozen, selection: .none, defaultAction: .standard,
                   defaultShortcut: .captureFullScreen)
        case .fullScreenToEditor:
            Preset(id: self, title: "Full Screen to Editor", screen: .frozen, selection: .none, defaultAction: .editor,
                   defaultShortcut: Shortcut(
                       keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(cmdKey | shiftKey | optionKey), key: "1"
                   ))
        case .captureScrolling:
            Preset(id: self, title: "Scrolling Capture", screen: .live, selection: .scrolling, defaultAction: .standard,
                   defaultShortcut: Shortcut(
                       keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | shiftKey | optionKey), key: "2"
                   ))
        case .liveArea:
            Preset(id: self, title: "Live Area", screen: .live, selection: .area, defaultAction: .standard,
                   defaultShortcut: nil)
        case .repeatArea:
            Preset(id: self, title: "Repeat Last Area", screen: .live, selection: .lastArea, defaultAction: .standard,
                   defaultShortcut: nil)
        case .delayedArea:
            Preset(id: self, title: "Delayed Area", screen: .frozen, selection: .area, defaultAction: .standard,
                   defaultShortcut: nil, delay: 3)
        }
    }
}

/// What a hotkey does (decision 4): which screen you aim at, how you pick, and what
/// Enter runs. Area's click-to-snap covers the "click a window" choice, so no v1
/// preset needs a window-only mode.
public struct Preset: Equatable, Sendable {
    public enum Screen: Sendable {
        /// The screen stops the instant the hotkey fires; you aim at a still frame.
        case frozen
        /// You aim at the moving screen; the pixels are taken when you let go.
        case live
    }

    public enum Selection: Sendable {
        /// The display under the pointer, nothing to pick.
        case none
        /// Drag a rectangle; a click snaps to the window under the pointer.
        case area
        /// The rectangle the last area capture used, nothing to pick.
        case lastArea
        /// Drag a rectangle, then the page scrolls under it (M5).
        case scrolling
    }

    public let id: PresetID
    public let title: String
    public let screen: Screen
    public let selection: Selection
    /// What Enter runs unless Settings picked something else.
    public let defaultAction: CaptureAction
    public let defaultShortcut: Shortcut?
    /// Countdown seconds before the screen freezes; 0 for none.
    public let delay: Int

    public static let delayChoices = [3, 5, 10]

    init(
        id: PresetID, title: String, screen: Screen, selection: Selection, defaultAction: CaptureAction,
        defaultShortcut: Shortcut?, delay: Int = 0
    ) {
        self.id = id
        self.title = title
        self.screen = screen
        self.selection = selection
        self.defaultAction = defaultAction
        self.defaultShortcut = defaultShortcut
        self.delay = delay
    }

    /// Scrolling capture hands its stitched image on by itself (M5), so its Enter isn't
    /// a choice yet.
    public var hasConfigurableAction: Bool { selection != .scrolling }

    /// One line for Settings: the screen and how you pick.
    public var summary: String {
        let screen = screen == .frozen ? "Frozen" : "Live"
        let pick = switch selection {
        case .none: id == .fullScreenToEditor ? "crop in the editor" : "the display under the mouse"
        case .area: delay > 0 ? "countdown, then drag or click a window" : "drag, or click a window"
        case .lastArea: "the last area again, nothing to pick"
        case .scrolling: "drag, then scroll"
        }
        return "\(screen) · \(pick)"
    }

    /// The Enter action to run: the stored choice if this version knows it, else the
    /// default. A stored workflow that has since been removed falls back too.
    public func action(stored name: String?, installedWorkflows: Set<String> = []) -> CaptureAction {
        guard hasConfigurableAction, let name, let action = CaptureAction(name: name) else { return defaultAction }
        if let id = action.workflowID, !installedWorkflows.contains(id) { return defaultAction }
        return action
    }

    /// A stored countdown, kept to the offered choices.
    public func delay(stored seconds: Int?) -> Int {
        guard delay > 0 else { return 0 }
        guard let seconds, Self.delayChoices.contains(seconds) else { return delay }
        return seconds
    }
}

extension OverlayGeometry {
    /// The whole pixels under a view rectangle (bottom-left origin points), cut to the
    /// image — the inverse of `viewRect(for:)`, for repeating a remembered area.
    public func pixelRect(forView r: CGRect) -> PixelRect? {
        let x0 = Int((r.minX * scale).rounded()), x1 = Int((r.maxX * scale).rounded())
        let y0 = Int(((pointSize.height - r.maxY) * scale).rounded())
        let y1 = Int(((pointSize.height - r.minY) * scale).rounded())
        return PixelRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0).clamped(to: pixelSize)
    }
}

extension GlobalCoordinates {
    /// A CoreGraphics global rectangle (top-left of the main screen, y down), such as a
    /// window's bounds → Cocoa global (bottom-left of the main screen, y up).
    public static func cocoaRect(fromCG r: CGRect, mainScreenHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: mainScreenHeight - r.maxY, width: r.width, height: r.height)
    }
}
