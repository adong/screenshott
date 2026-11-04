import AppKit
import ScreenshottCore

/// Opens and tracks editor windows. While one is open Screenshott becomes a regular
/// app — Dock icon, ⌘Tab, a menu bar with Edit and View — and goes back to living in
/// the menu bar when the last one closes.
///
/// The ways in: the overlay's E key and the "full screen → editor" preset (through
/// `Delivery.Action.editor`, which saves the capture first), a click on a thumbnail,
/// Open With in Finder, and the menu bar's "Open in Editor…".
@MainActor
final class Editors {
    private var controllers: [EditorWindowController] = []
    private let preferences: Preferences
    private let store: ProjectStore

    init(preferences: Preferences, store: ProjectStore = .standard) {
        self.preferences = preferences
        self.store = store
    }

    /// A capture already saved as `file`: it opens as that file, so ⌘S updates it.
    /// Without a file it is a new, unsaved document that ⌘S names.
    @discardableResult
    func open(_ image: CGImage, scale: CGFloat, png: Data? = nil, file: URL? = nil) -> EditorWindowController {
        let id = UUID()
        let document = EditorDocument(imageSize: PixelSize(width: image.width, height: image.height), scale: scale, imageID: id)
        return present(EditorWindowController(
            document: document, images: [id: image], originals: png.map { [id: $0] } ?? [:], file: file,
            preferences: preferences, store: store
        ))
    }

    /// Opens a PNG, continuing its project if it was edited before.
    @discardableResult
    func open(file url: URL) -> EditorWindowController? {
        if let open = controllers.first(where: { $0.file?.standardizedFileURL == url.standardizedFileURL }) {
            NSApp.activate()
            open.show()
            return open
        }
        do {
            if let project = try store.load(forPNGNamed: url.lastPathComponent) {
                var images: [UUID: CGImage] = [:], originals: [UUID: Data] = [:]
                for (id, original) in project.originals {
                    let data = try Data(contentsOf: original)
                    guard let image = ImageFile.load(data)?.image else { throw CaptureError.encodeFailed }
                    images[id] = image
                    originals[id] = data
                }
                Log.write("editor reopened \(url.lastPathComponent): \(project.document.annotations.count) annotation(s)")
                return present(EditorWindowController(
                    document: project.document, images: images, originals: originals, file: url,
                    preferences: preferences, store: store
                ))
            }
        } catch {
            Log.write("editor: project for \(url.lastPathComponent) unreadable (\(error)); opening the PNG itself")
        }
        guard let data = try? Data(contentsOf: url), let (image, scale) = ImageFile.load(data) else {
            Log.write("editor: can't read \(url.path)")
            NSSound.beep()
            return nil
        }
        Log.write("editor opened \(url.lastPathComponent) \(image.width)x\(image.height) @\(Int(scale))x")
        return open(image, scale: scale, png: data, file: url)
    }

    /// "Open in Editor…": any image, with a picker that starts in the save folder.
    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        panel.directoryURL = preferences.saveDirectory
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(file: url)
    }

    // MARK: - Combine (M4)

    /// Starts an area capture and says whether its overlay came up. Set by the app
    /// delegate, which owns capturing.
    var startAreaCapture: (() async -> Bool)?
    /// The editor whose Add Capture was pressed: the next capture goes onto its canvas.
    private weak var appendTarget: EditorWindowController?

    /// Hides the editor so it isn't in the shot, then starts an area capture.
    func addCapture(to controller: EditorWindowController) {
        guard let startAreaCapture else { return NSSound.beep() }
        appendTarget = controller
        controller.window?.orderOut(nil)
        Task {
            // Let the window server take the editor off screen before the freeze.
            try? await Task.sleep(for: .milliseconds(150))
            if await !startAreaCapture() { captureCancelled() }
        }
    }

    /// The thumbnail's Add Capture: opens that capture, then adds to it.
    func addCapture(toFile url: URL) {
        if let controller = open(file: url) { addCapture(to: controller) }
    }

    /// Hands a finished capture to the editor waiting for one. False when none is.
    func append(_ image: CGImage, scale: CGFloat) -> Bool {
        guard let target = appendTarget else { return false }
        appendTarget = nil
        target.append(image, scale: scale)
        NSApp.activate()
        target.show()
        return true
    }

    /// The overlay closed without a capture: the editor comes back as it was.
    func captureCancelled() {
        guard let target = appendTarget else { return }
        appendTarget = nil
        NSApp.activate()
        target.show()
    }

    /// Before quitting: each editor with unsaved changes asks. False if one was cancelled.
    func resolveUnsavedChanges() -> Bool {
        controllers.allSatisfy { $0.resolveUnsavedChanges() }
    }

    @discardableResult
    private func present(_ controller: EditorWindowController) -> EditorWindowController {
        controllers.append(controller)
        controller.onClose = { [weak self] closed in self?.closed(closed) }
        controller.onAddCapture = { [weak self] editor in self?.addCapture(to: editor) }
        EditorMenu.install()
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        NSApp.activate()
        controller.show()
        return controller
    }

    private func closed(_ controller: EditorWindowController) {
        controllers.removeAll { $0 === controller }
        if controllers.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }
}

/// The main menu. Hidden while Screenshott is a menu bar app, but its key equivalents
/// still work there — which is also what gives text fields ⌘C, ⌘V and ⌘Z.
@MainActor
enum EditorMenu {
    static func install() {
        guard NSApp.mainMenu == nil || NSApp.mainMenu?.item(withTitle: "Edit") == nil else { return }
        let main = NSMenu()
        main.addItem(submenu("Screenshott", [
            item("Settings…", #selector(AppDelegate.openSettings), ","),
            .separator(),
            item("Hide Screenshott", #selector(NSApplication.hide(_:)), "h"),
            item("Quit Screenshott", #selector(NSApplication.terminate(_:)), "q"),
        ]))
        main.addItem(submenu("File", [
            item("Add Capture", #selector(EditorWindowController.addCapture(_:)), "A"),
            item("Save", #selector(EditorWindowController.saveDocument(_:)), "s"),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
        ]))
        main.addItem(submenu("Edit", [
            item("Undo", #selector(CanvasView.undo(_:)), "z"),
            item("Redo", #selector(CanvasView.redo(_:)), "Z"),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Delete", #selector(NSText.delete(_:)), ""),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ]))
        main.addItem(submenu("View", [
            item("Zoom In", #selector(EditorWindowController.zoomIn(_:)), "="),
            item("Zoom Out", #selector(EditorWindowController.zoomOut(_:)), "-"),
            item("Actual Size", #selector(EditorWindowController.zoomToActualSize(_:)), "0"),
            item("Zoom to Fit", #selector(EditorWindowController.zoomToFit(_:)), "9"),
        ]))
        main.addItem(submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
        ]))
        NSApp.mainMenu = main
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        for child in items { menu.addItem(child) }
        item.submenu = menu
        return item
    }

    /// Target nil: the action goes to whatever in the key window answers it.
    private static func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        NSMenuItem(title: title, action: action, keyEquivalent: key)
    }
}
