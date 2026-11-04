import Foundation

/// What happens to a finished capture. The built-in actions and installed workflows
/// share this one interface (#10): a preset's Enter runs one, the overlay keys, the
/// action bar and the thumbnail menu pick others, and a workflow's `action` steps
/// name them.
public enum CaptureAction: Hashable, Sendable {
    /// Save to the folder; copy and show a thumbnail unless Settings turned them off.
    case standard
    case copyOnly
    /// Save to the folder, nothing else.
    case save
    /// A save panel instead of the archive folder.
    case saveAs
    /// Save to the folder and show the thumbnail, no copy.
    case thumbnail
    /// Save to the folder, then open the editor on that file (M3). No copy or thumbnail.
    case editor
    /// An installed workflow, by its id.
    case workflow(String)

    /// What Settings offers as a preset's Enter action, before the installed workflows.
    public static let presetChoices: [CaptureAction] = [.standard, .copyOnly, .saveAs, .editor]

    /// The built-ins a workflow's `action` step may name. `standard` is left out: a
    /// workflow says which of copy / save / thumbnail it wants.
    public static let workflowSteps: [CaptureAction] = [.copyOnly, .save, .saveAs, .thumbnail, .editor]

    private static let builtIn: [CaptureAction] = [.standard, .copyOnly, .save, .saveAs, .thumbnail, .editor]

    /// Stable name for UserDefaults and for `workflow.json` action steps.
    public var name: String {
        switch self {
        case .standard: "standard"
        case .copyOnly: "copy"
        case .save: "save"
        case .saveAs: "save-as"
        case .thumbnail: "thumbnail"
        case .editor: "editor"
        case .workflow(let id): "workflow:\(id)"
        }
    }

    public init?(name: String) {
        if name.hasPrefix("workflow:") {
            let id = String(name.dropFirst("workflow:".count))
            guard WorkflowManifest.isValidID(id) else { return nil }
            self = .workflow(id)
            return
        }
        guard let action = Self.builtIn.first(where: { $0.name == name }) else { return nil }
        self = action
    }

    /// Menu and picker title. A workflow's title is its name, which only the app knows.
    public var title: String {
        switch self {
        case .standard: "Copy, save, thumbnail"
        case .copyOnly: "Copy only"
        case .save: "Save to folder"
        case .saveAs: "Save As…"
        case .thumbnail: "Show thumbnail"
        case .editor: "Open in editor"
        case .workflow(let id): id
        }
    }

    public var workflowID: String? {
        if case .workflow(let id) = self { return id }
        return nil
    }
}
