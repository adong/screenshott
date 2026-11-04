import AppKit
import ScreenshottCore

/// One editor window: the toolbar, the zoomable canvas, and saving. ⌘S writes the
/// flattened PNG to `file` (the capture it was opened from, or a new name in the save
/// folder) and the project — originals plus objects — to ProjectStore under the same
/// name, so reopening that PNG picks up where this left off (decision 7a).
@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    let model: EditorModel
    /// The PNG this document saves to.
    private(set) var file: URL?
    var onClose: ((EditorWindowController) -> Void)?
    /// Add Capture was pressed (M4).
    var onAddCapture: ((EditorWindowController) -> Void)?

    private let preferences: Preferences
    private let store: ProjectStore
    private let canvas: CanvasView
    private let scrollView = NSScrollView()
    let toolbar: EditorToolbar
    private let combine: CombineControls
    /// Sized and centered once; hiding for Add Capture keeps the zoom and position.
    private var placed = false
    /// Each capture's original PNG bytes, for the project folder. A capture opened from
    /// a file reuses its bytes; others are encoded on the first save.
    private var originals: [UUID: Data]

    init(
        document: EditorDocument, images: [UUID: CGImage], originals: [UUID: Data], file: URL?,
        preferences: Preferences, store: ProjectStore
    ) {
        model = EditorModel(document: document, images: images)
        self.file = file
        self.originals = originals
        self.preferences = preferences
        self.store = store
        canvas = CanvasView(model: model)

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 720, height: 360)
        window.tabbingMode = .disallowed
        toolbar = EditorToolbar(model: model)
        combine = CombineControls(model: model)
        toolbar.insert([combine])
        super.init(window: window)

        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .bottom
        accessory.view = toolbar
        window.addTitlebarAccessoryViewController(accessory)

        scrollView.contentView = CenteringClipView()
        scrollView.documentView = canvas
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.05
        scrollView.maxMagnification = 16
        scrollView.backgroundColor = .underPageBackgroundColor
        scrollView.drawsBackground = true
        window.contentView = scrollView
        window.delegate = self
        window.initialFirstResponder = canvas

        toolbar.dragWell.provide = { [weak self] in self?.fileForDrag() }
        model.onChange = { [weak self] in self?.modelChanged() }
        NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveMagnifyNotification, object: scrollView, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.canvas.needsDisplay = true } }
        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Brings the window forward, sized to the canvas the first time.
    func show() {
        guard let window else { return }
        if !placed {
            placed = true
            fitToCanvas(on: ScreenCapturer.screenUnderMouse ?? NSScreen.main)
        }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
    }

    /// Sizes the window to show the whole canvas at 100%, or smaller to fit in 85% of
    /// the screen, and centers it there.
    private func fitToCanvas(on screen: NSScreen?) {
        guard let window else { return }
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let canvasSize = canvas.frame.size
        let chrome = window.frameRect(forContentRect: .zero).height + EditorToolbar.height
        let fit = min(
            1, visible.width * 0.85 / max(canvasSize.width, 1), (visible.height * 0.85 - chrome) / max(canvasSize.height, 1)
        )
        window.setContentSize(CGSize(
            width: max(canvasSize.width * fit + 2, window.minSize.width),
            height: max(canvasSize.height * fit + 2, window.minSize.height - chrome)
        ))
        scrollView.magnification = fit
        let frame = window.frame
        window.setFrameOrigin(CGPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2))
    }

    private func modelChanged() {
        canvas.modelChanged()
        toolbar.update()
        combine.update()
        window?.isDocumentEdited = model.isDirty
    }

    private func updateTitle() {
        window?.title = file?.deletingPathExtension().lastPathComponent ?? "New Capture"
        window?.representedURL = file
    }

    // MARK: - Saving

    /// Writes the project, then the PNG — in that order, so a capture whose only copy
    /// is the PNG is safe in the project folder before the PNG is overwritten.
    @discardableResult
    func save() -> URL? {
        canvas.endEditing()
        if canvas.isCropping { canvas.applyCrop() }
        let clock = ContinuousClock()
        let start = clock.now
        let document = model.document
        guard let image = CanvasRenderer.flatten(document, images: model.images),
              let png = PNGEncoder.data(from: image, scale: document.scale)
        else {
            Log.write("editor: flatten failed")
            NSSound.beep()
            return nil
        }
        let url = file ?? ScreenshotNaming.uniqueURL(
            in: preferences.saveDirectory, fileName: ScreenshotNaming.fileName(for: Date())
        ) { FileManager.default.fileExists(atPath: $0.path) }
        do {
            try store.save(document, forPNGNamed: url.lastPathComponent) { [self] id in originalPNG(id) }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url, options: .atomic)
        } catch {
            Log.write("editor: save \(url.lastPathComponent) failed: \(error)")
            NSSound.beep()
            return nil
        }
        file = url
        model.markSaved()
        updateTitle()
        Log.write(String(
            format: "editor saved %@ %dx%d %d capture(s) %d annotation(s) in %.1fms",
            url.lastPathComponent, image.width, image.height, document.images.count, document.annotations.count,
            (clock.now - start).milliseconds
        ))
        return url
    }

    private func originalPNG(_ id: UUID) -> Data? {
        if let data = originals[id] { return data }
        guard let image = model.images[id], let data = PNGEncoder.data(from: image, scale: model.document.scale) else {
            return nil
        }
        originals[id] = data
        return data
    }

    /// The saved PNG, saving first only if something changed.
    private func fileForDrag() -> (file: URL, image: NSImage)? {
        guard let url = (model.isDirty ? nil : file) ?? save(), let image = NSImage(contentsOf: url) else { return nil }
        return (url, image)
    }

    // MARK: - Menu actions

    @objc func saveDocument(_ sender: Any?) { save() }

    /// Combine: the next capture goes onto this canvas (decision 3).
    @objc func addCapture(_ sender: Any?) {
        canvas.endEditing()
        if canvas.isCropping { canvas.applyCrop() }
        onAddCapture?(self)
    }

    /// Appends a capture, resampled to this canvas's scale if it came from a display
    /// with another one, and resizes the window around the bigger canvas.
    func append(_ image: CGImage, scale: CGFloat) {
        let document = model.document
        let factor = document.scale / scale
        let size = PixelSize(
            width: max(1, Int((CGFloat(image.width) * factor).rounded())),
            height: max(1, Int((CGFloat(image.height) * factor).rounded()))
        )
        guard let pixels = ImageScaling.resized(image, to: size) else { return NSSound.beep() }
        let id = UUID()
        model.addImage(pixels, id: id)
        model.edit("Add Capture") { $0.append(imageOf: size, id: id) }
        model.selection = nil
        model.selectedImage = nil
        Log.write("editor added capture \(size.width)x\(size.height), \(model.document.images.count) on the canvas")
        fitToCanvas(on: window?.screen ?? ScreenCapturer.screenUnderMouse)
    }

    @objc func copy(_ sender: Any?) {
        canvas.endEditing()
        guard let image = CanvasRenderer.flatten(model.document, images: model.images),
              let png = PNGEncoder.data(from: image, scale: model.document.scale)
        else { return NSSound.beep() }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        Log.write("editor copied \(image.width)x\(image.height)")
    }

    @objc func zoomIn(_ sender: Any?) { zoom(by: 2) }
    @objc func zoomOut(_ sender: Any?) { zoom(by: 0.5) }
    @objc func zoomToActualSize(_ sender: Any?) { zoom(to: 1) }

    @objc func zoomToFit(_ sender: Any?) {
        scrollView.magnify(toFit: canvas.bounds)
        canvas.needsDisplay = true
    }

    private func zoom(by factor: CGFloat) { zoom(to: scrollView.magnification * factor) }

    private func zoom(to magnification: CGFloat) {
        let clip = scrollView.contentView.bounds
        scrollView.setMagnification(magnification, centeredAt: CGPoint(x: clip.midX, y: clip.midY))
        canvas.needsDisplay = true
    }

    // MARK: - Window

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { model.undoManager }

    /// Unsaved changes ask first: Save, Don't Save or Cancel.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        canvas.endEditing()
        guard model.isDirty else { return true }
        unsavedAlert().beginSheetModal(for: sender) { [weak self] response in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch response {
                case .alertFirstButtonReturn:
                    if self.save() != nil { sender.close() }
                case .alertThirdButtonReturn:
                    self.model.markSaved()
                    sender.close()
                default:
                    break
                }
            }
        }
        return false
    }

    /// For Quit: the same question, asked modally. False means Cancel.
    func resolveUnsavedChanges() -> Bool {
        canvas.endEditing()
        guard model.isDirty else { return true }
        show()
        switch unsavedAlert().runModal() {
        case .alertFirstButtonReturn: return save() != nil
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    private func unsavedAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Save changes to \(window?.title ?? "this capture")?"
        alert.informativeText = "Your annotations are lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")
        return alert
    }

    func windowWillClose(_ notification: Notification) {
        onClose?(self)
    }
}

/// Keeps a canvas smaller than the window in the middle instead of the bottom-left.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView else { return rect }
        if rect.width > document.frame.width { rect.origin.x = (document.frame.width - rect.width) / 2 }
        if rect.height > document.frame.height { rect.origin.y = (document.frame.height - rect.height) / 2 }
        return rect
    }
}
