import Foundation

/// What happens to a finished capture. Every built-in action goes through this one
/// interface, so #10's workflows can plug in as one more kind: a preset's Enter runs
/// one, and the overlay keys, its action bar and the thumbnail menu pick others.
public enum CaptureAction: Hashable, Sendable {
    /// Save to the folder; copy and show a thumbnail unless Settings turned them off.
    case standard
    case copyOnly
    /// Save to the folder, nothing else.
    case save
    /// A save panel instead of the archive folder.
    case saveAs
    case thumbnail
    case openEditor

    /// What Settings offers as a preset's Enter action.
    public static let presetChoices: [CaptureAction] = [.standard, .copyOnly, .saveAs, .openEditor]

    private static let builtIn: [CaptureAction] = [.standard, .copyOnly, .save, .saveAs, .thumbnail, .openEditor]

    /// Stable name for UserDefaults.
    public var name: String {
        switch self {
        case .standard: "standard"
        case .copyOnly: "copy"
        case .save: "save"
        case .saveAs: "save-as"
        case .thumbnail: "thumbnail"
        case .openEditor: "editor"
        }
    }

    public init?(name: String) {
        guard let action = Self.builtIn.first(where: { $0.name == name }) else { return nil }
        self = action
    }

    /// Menu and picker title.
    public var title: String {
        switch self {
        case .standard: "Copy, save, thumbnail"
        case .copyOnly: "Copy only"
        case .save: "Save to folder"
        case .saveAs: "Save As…"
        case .thumbnail: "Show thumbnail"
        case .openEditor: "Open in editor"
        }
    }
}
