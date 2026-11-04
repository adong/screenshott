import AppKit
import ScreenshottCore

/// The narrow strip at the screen edge that shows the stitch growing during a
/// scrolling capture, so a bad seam is visible while there is still time to cancel.
/// It always shows the end of the stitch, what Enter would save (less the scroller band,
/// if that gets cut). Ours, so it is left out of the capture.
@MainActor
final class ScrollPreview {
    static let width: CGFloat = 132

    let panel: NSPanel
    private let clip = CALayer()
    private let content = CALayer()
    private let pending = CALayer()
    private let title = CATextLayer()
    private let detail = CATextLayer()
    /// Strip points per output pixel row.
    private let pointsPerRow: CGFloat
    private var writtenRows = 0
    private var pendingRows = 0
    private var mode = "Scrolling"
    private var note = ""
    private var height = 0

    /// The stitch's height, then the keys or a warning.
    private var detailText: String { height > 0 ? "\(height.formatted()) px\n\(note)" : note }

    /// Opposite the region's side of `screen`, so it never covers what is captured.
    init(on screen: NSScreen, avoiding region: CGRect, regionPixelWidth: Int) {
        let visible = screen.visibleFrame
        let margin: CGFloat = 12
        let x = region.midX > visible.midX ? visible.minX + margin : visible.maxX - margin - Self.width
        let frame = CGRect(x: x, y: visible.minY + margin, width: Self.width, height: visible.height - 2 * margin)
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none

        let scale = screen.backingScaleFactor
        let inner = Self.width - 12
        pointsPerRow = inner / CGFloat(max(regionPixelWidth, 1))

        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        let root = CALayer()
        view.layer = root
        view.wantsLayer = true
        root.backgroundColor = NSColor(white: 0.08, alpha: 0.86).cgColor
        root.cornerRadius = 10
        root.borderColor = NSColor(white: 1, alpha: 0.18).cgColor
        root.borderWidth = 1

        for (layer, size, weight) in [(title, 12.0, NSFont.Weight.semibold), (detail, 10.5, .regular)] {
            let font = NSFont.systemFont(ofSize: size, weight: weight)
            layer.font = font
            layer.fontSize = size
            layer.foregroundColor = NSColor.white.withAlphaComponent(weight == .regular ? 0.7 : 1).cgColor
            layer.contentsScale = scale
            layer.alignmentMode = .center
            layer.isWrapped = true
            root.addSublayer(layer)
        }
        title.frame = CGRect(x: 4, y: frame.height - 26, width: inner + 4, height: 16)
        detail.frame = CGRect(x: 4, y: frame.height - 82, width: inner + 4, height: 54)

        clip.frame = CGRect(x: 6, y: 6, width: inner, height: frame.height - 92)
        clip.masksToBounds = true
        clip.isGeometryFlipped = true
        clip.backgroundColor = NSColor(white: 0, alpha: 0.4).cgColor
        clip.cornerRadius = 4
        content.anchorPoint = .zero
        content.isGeometryFlipped = false
        pending.contentsGravity = .resize
        pending.magnificationFilter = .linear
        content.addSublayer(pending)
        clip.addSublayer(content)
        root.addSublayer(clip)
        panel.contentView = view
        setStatus(mode, detail: "")
    }

    func show() { panel.orderFrontRegardless() }

    func close() { panel.orderOut(nil) }

    /// `mode` on the first line; `text` (keys, or a warning in orange) under the height.
    func setStatus(_ mode: String, detail text: String, warning: Bool = false) {
        self.mode = mode
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        title.string = mode
        note = text
        detail.string = detailText
        detail.foregroundColor = (warning ? NSColor.systemOrange : NSColor.white.withAlphaComponent(0.7)).cgColor
        CATransaction.commit()
    }

    func update(_ preview: ScrollSession.Preview, height: Int) {
        self.height = height
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        detail.string = detailText
        let width = clip.bounds.width
        if let image = preview.written, preview.writtenRows > 0 {
            let segment = CALayer()
            segment.contents = image
            segment.contentsGravity = .resize
            segment.frame = CGRect(
                x: 0, y: CGFloat(writtenRows) * pointsPerRow, width: width, height: CGFloat(preview.writtenRows) * pointsPerRow
            )
            content.addSublayer(segment)
            writtenRows += preview.writtenRows
        }
        pendingRows = preview.pendingRows
        pending.contents = preview.pending
        pending.frame = CGRect(
            x: 0, y: CGFloat(writtenRows) * pointsPerRow, width: width, height: CGFloat(pendingRows) * pointsPerRow
        )
        // Keep the end in view once the stitch is taller than the strip.
        let total = CGFloat(writtenRows + pendingRows) * pointsPerRow
        content.frame = CGRect(x: 0, y: min(0, clip.bounds.height - total), width: width, height: total)
    }

    /// A short orange flash around the strip: that frame didn't fit.
    func flash() {
        guard let root = panel.contentView?.layer else { return }
        let pulse = CABasicAnimation(keyPath: "borderColor")
        pulse.fromValue = NSColor.systemOrange.cgColor
        pulse.toValue = root.borderColor
        pulse.duration = 0.6
        root.add(pulse, forKey: "flash")
    }
}
