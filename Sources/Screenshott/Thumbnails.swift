import AppKit
import ScreenshottCore

/// The floating thumbnails in the bottom-right corner after a capture. Each one can be
/// dragged out as the PNG file, clicked to open it, or dismissed; they stack upward
/// per screen and go away on their own after a few seconds.
@MainActor
final class Thumbnails {
    private var items: [ThumbnailItem] = []
    private static let perScreenLimit = 5
    /// Runs an after-capture action on a thumbnail's capture; Delivery sets it.
    var onAction: ((CaptureAction, CaptureItem) -> Void)?
    /// The installed workflows, offered in each thumbnail's menu.
    var workflows: () -> [(name: String, action: CaptureAction)] = { [] }

    /// Window numbers to leave out of the next capture.
    var windowNumbers: Set<Int> { Set(items.map(\.panel.windowNumber)) }

    func show(_ image: CGImage, scale: CGFloat, file: URL, on screen: NSScreen?) {
        guard let screen = screen ?? NSScreen.main else { return }
        let size = ThumbnailLayout.size(for: PixelSize(width: image.width, height: image.height), scale: scale)
        let item = ThumbnailItem(
            image: image, scale: scale, file: file, size: size, visibleFrame: screen.visibleFrame, workflows: workflows()
        )
        item.onAction = { [weak self] action, capture in self?.onAction?(action, capture) }
        item.onDismiss = { [weak self, weak item] in
            guard let self, let item else { return }
            items.removeAll { $0 === item }
            relayout()
        }
        items.append(item)
        let crowd = items.filter { $0.visibleFrame == item.visibleFrame }
        if crowd.count > Self.perScreenLimit { crowd.first?.dismiss() }
        relayout()
        item.present()
    }

    private func relayout() {
        var screens: [CGRect] = []
        for item in items where !screens.contains(item.visibleFrame) { screens.append(item.visibleFrame) }
        for visibleFrame in screens {
            let stack = items.filter { $0.visibleFrame == visibleFrame }
            let frames = ThumbnailLayout.frames(sizes: stack.map(\.size), in: visibleFrame)
            for (item, frame) in zip(stack, frames) { item.move(to: frame) }
        }
    }
}

@MainActor
final class ThumbnailItem {
    let panel: NSPanel
    let file: URL
    let size: CGSize
    let visibleFrame: CGRect
    var onDismiss: (() -> Void)?
    var onAction: ((CaptureAction, CaptureItem) -> Void)?

    private let image: CGImage
    private let scale: CGFloat
    private let workflows: [(name: String, action: CaptureAction)]
    private var timer: Timer?
    private var placed = false
    private var dismissed = false
    private static let lifetime: TimeInterval = 6

    init(
        image: CGImage, scale: CGFloat, file: URL, size: CGSize, visibleFrame: CGRect,
        workflows: [(name: String, action: CaptureAction)]
    ) {
        self.image = image
        self.scale = scale
        self.workflows = workflows
        self.file = file
        self.size = size
        self.visibleFrame = visibleFrame
        panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.alphaValue = 0

        let view = ThumbnailView(frame: CGRect(origin: .zero, size: size), image: image)
        view.onHover = { [weak self] inside in self?.hovered(inside) }
        view.onClick = { [weak self] in self?.open() }
        view.onDragEnded = { [weak self] delivered in if delivered { self?.dismiss() } }
        view.onClose = { [weak self] in self?.dismiss() }
        view.hasWorkflows = !workflows.isEmpty
        view.menu = menu()
        view.file = file
        panel.contentView = view
    }

    func present() {
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        startTimer()
    }

    func move(to frame: CGRect) {
        guard placed else {
            panel.setFrame(frame, display: false)
            placed = true
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().setFrame(frame, display: true)
        }
    }

    func dismiss() {
        guard !dismissed else { return }
        dismissed = true
        timer?.invalidate()
        onDismiss?()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 0 }
        let panel = panel
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            panel.orderOut(nil)
        }
    }

    private func hovered(_ inside: Bool) {
        // Never vanish from under the pointer.
        if inside { timer?.invalidate() } else { startTimer() }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.lifetime, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    // MARK: - Actions

    /// Preview for now; the M3 editor takes over.
    private func open() {
        NSWorkspace.shared.open(file)
        dismiss()
    }

    private func menu() -> NSMenu {
        let menu = NSMenu()
        for (title, action) in [
            ("Copy", #selector(ThumbnailMenuTarget.copyImage)),
            ("Show in Finder", #selector(ThumbnailMenuTarget.reveal)),
            ("Open", #selector(ThumbnailMenuTarget.open)),
            ("Open in Editor", #selector(ThumbnailMenuTarget.openInEditor)),
            ("Move to Trash", #selector(ThumbnailMenuTarget.trash)),
        ] {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = menuTarget
        }
        if !workflows.isEmpty {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Workflows", action: nil, keyEquivalent: "").isEnabled = false
            for (index, workflow) in workflows.enumerated() {
                let item = menu.addItem(
                    withTitle: workflow.name, action: #selector(ThumbnailMenuTarget.runWorkflow(_:)), keyEquivalent: ""
                )
                item.target = menuTarget
                item.tag = index
                item.indentationLevel = 1
            }
        }
        return menu
    }

    private lazy var menuTarget = ThumbnailMenuTarget(item: self)

    fileprivate func copyFile() {
        guard let png = try? Data(contentsOf: file) else { return NSSound.beep() }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
    }

    fileprivate func revealFile() {
        NSWorkspace.shared.activateFileViewerSelecting([file])
        dismiss()
    }

    fileprivate func openFile() { open() }

    fileprivate func runWorkflow(at index: Int) {
        guard workflows.indices.contains(index) else { return }
        run(workflows[index].action)
    }

    /// Hands the capture to an after-capture action, then gets out of the way.
    fileprivate func run(_ action: CaptureAction) {
        onAction?(action, CaptureItem(image: image, scale: scale, screen: nil, preset: nil, file: file))
        dismiss()
    }

    fileprivate func trashFile() {
        do {
            try FileManager.default.trashItem(at: file, resultingItemURL: nil)
            Log.write("thumbnail moved \(file.lastPathComponent) to Trash")
            dismiss()
        } catch {
            Log.write("thumbnail trash failed: \(error)")
            NSSound.beep()
        }
    }
}

/// NSMenuItem needs an Objective-C target; this forwards to the item.
@MainActor
private final class ThumbnailMenuTarget: NSObject {
    weak var item: ThumbnailItem?
    init(item: ThumbnailItem) { self.item = item }
    @objc func copyImage() { item?.copyFile() }
    @objc func reveal() { item?.revealFile() }
    @objc func open() { item?.openFile() }
    @objc func openInEditor() { item?.run(.openEditor) }
    @objc func runWorkflow(_ sender: NSMenuItem) { item?.runWorkflow(at: sender.tag) }
    @objc func trash() { item?.trashFile() }
}

@MainActor
final class ThumbnailView: NSView, NSDraggingSource {
    var onHover: ((Bool) -> Void)?
    var onClick: (() -> Void)?
    var onDragEnded: ((Bool) -> Void)?
    var onClose: (() -> Void)?
    var file: URL?
    /// Shows a bolt on hover that opens the menu, where the workflows are.
    var hasWorkflows = false

    private let image: CGImage
    private let closeButton = NSButton()
    private let workflowsButton = NSButton()
    private var pressPoint: CGPoint?
    private var dragging = false

    init(frame: CGRect, image: CGImage) {
        self.image = image
        super.init(frame: frame)
        wantsLayer = true
        guard let layer else { return }
        layer.cornerRadius = 8
        layer.masksToBounds = true
        layer.backgroundColor = NSColor(white: 0.12, alpha: 0.92).cgColor
        layer.borderColor = NSColor(white: 1, alpha: 0.25).cgColor
        layer.borderWidth = 1

        let picture = CALayer()
        picture.contents = image
        picture.contentsGravity = .resizeAspect
        picture.frame = bounds.insetBy(dx: 1, dy: 1)
        layer.addSublayer(picture)

        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        closeButton.isBordered = false
        closeButton.contentTintColor = .white
        closeButton.target = self
        closeButton.action = #selector(close)
        closeButton.frame = CGRect(x: 4, y: bounds.height - 24, width: 20, height: 20)
        closeButton.isHidden = true
        addSubview(closeButton)

        workflowsButton.image = NSImage(systemSymbolName: "bolt.circle.fill", accessibilityDescription: "Workflows")
        workflowsButton.isBordered = false
        workflowsButton.contentTintColor = .white
        workflowsButton.target = self
        workflowsButton.action = #selector(showWorkflows)
        workflowsButton.frame = CGRect(x: bounds.width - 24, y: bounds.height - 24, width: 20, height: 20)
        workflowsButton.isHidden = true
        addSubview(workflowsButton)

        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self
        ))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) {
        closeButton.isHidden = false
        workflowsButton.isHidden = !hasWorkflows
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        closeButton.isHidden = true
        workflowsButton.isHidden = true
        onHover?(false)
    }

    override func mouseDown(with event: NSEvent) {
        pressPoint = convert(event.locationInWindow, from: nil)
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let pressPoint, !dragging, let file else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard hypot(p.x - pressPoint.x, p.y - pressPoint.y) > 3 else { return }
        dragging = true
        // The file URL is what Finder, Slack, Mail and browsers all accept.
        let item = NSDraggingItem(pasteboardWriter: file as NSURL)
        item.setDraggingFrame(bounds, contents: NSImage(cgImage: image, size: bounds.size))
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressPoint = nil }
        if pressPoint != nil, !dragging { onClick?() }
    }

    @objc private func close() { onClose?() }

    @objc private func showWorkflows() {
        menu?.popUp(positioning: nil, at: CGPoint(x: workflowsButton.frame.minX, y: workflowsButton.frame.minY), in: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    /// `dragging` stays set until the next press, so a late mouse-up can't count as a click.
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDragEnded?(operation != [])
    }
}
