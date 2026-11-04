import AppKit

/// A dark rounded panel in the middle of a screen: the delayed capture's countdown, and
/// short messages (`Toast`). It never takes focus.
@MainActor
final class HUDPanel {
    let panel: NSPanel
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    var onClick: (() -> Void)? {
        didSet { (panel.contentView as? HUDView)?.onClick = onClick }
    }

    init(size: CGSize, titleSize: CGFloat) {
        panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        // Above everything but the overlay, which takes over when the countdown ends.
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none

        let view = HUDView(frame: CGRect(origin: .zero, size: size))
        for (field, font) in [
            (title, NSFont.monospacedDigitSystemFont(ofSize: titleSize, weight: .semibold)),
            (detail, NSFont.systemFont(ofSize: 11, weight: .medium)),
        ] {
            field.font = font
            field.textColor = field === title ? .white : NSColor(white: 1, alpha: 0.7)
            field.alignment = .center
            field.lineBreakMode = .byTruncatingTail
            field.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(field)
        }
        NSLayoutConstraint.activate([
            title.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -6),
            title.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -24),
            detail.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            detail.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -24),
        ])
        panel.contentView = view
    }

    /// `height` is where its middle goes, as a fraction of the screen from the bottom.
    func show(_ text: String, detail note: String = "", on screen: NSScreen, height: CGFloat = 0.5) {
        title.stringValue = text
        detail.stringValue = note
        let size = panel.frame.size
        let frame = screen.frame
        panel.setFrameOrigin(CGPoint(
            x: frame.midX - size.width / 2, y: frame.minY + frame.height * height - size.height / 2
        ))
        panel.orderFrontRegardless()
    }

    func update(_ text: String) { title.stringValue = text }

    func hide() { panel.orderOut(nil) }
}

private final class HUDView: NSView {
    var onClick: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.85).cgColor
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseUp(with event: NSEvent) { onClick?() }
}

/// A message that fades after a moment, low on the screen under the mouse:
/// what a workflow's `notify` shows, and why something didn't work.
@MainActor
enum Toast {
    private static var hud: HUDPanel?
    private static var hideTask: Task<Void, Never>?

    static func show(_ message: String, detail: String = "") {
        guard let screen = ScreenCapturer.screenUnderMouse ?? NSScreen.main else { return }
        let hud = hud ?? HUDPanel(size: CGSize(width: 360, height: 72), titleSize: 15)
        Self.hud = hud
        hud.show(message, detail: detail, on: screen, height: 0.2)
        hud.onClick = { hud.hide() }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(detail.isEmpty ? 2.5 : 4))
            if !Task.isCancelled { hud.hide() }
        }
    }
}
