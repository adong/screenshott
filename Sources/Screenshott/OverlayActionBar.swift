import AppKit
import ScreenshottCore

/// The row of actions under the overlay's selection: Copy, Save As, Editor and each
/// installed workflow, each with the key that does the same. Drawn into one layer, like
/// the size label and the loupe; OverlayView asks it what a click hit.
@MainActor
final class OverlayActionBar {
    struct Item {
        let title: String
        /// The overlay key that does the same, shown dimmed after the title.
        let key: String
        let symbol: String
        /// A workflow's own icon, drawn instead of the symbol.
        var icon: NSImage?
        let action: CaptureAction
    }

    /// At most nine workflows, so each one has a number key.
    static func items(workflows: [InstalledWorkflow]) -> [Item] {
        [
            Item(title: "Copy", key: "⌘C", symbol: "doc.on.doc", action: .copyOnly),
            Item(title: "Save As", key: "⌘S", symbol: "square.and.arrow.down", action: .saveAs),
            Item(title: "Editor", key: "E", symbol: "pencil.tip", action: .editor),
        ] + workflows.prefix(9).enumerated().map { index, workflow in
            Item(title: workflow.name, key: "\(index + 1)", symbol: "bolt.fill", icon: workflow.icon, action: .workflow(workflow.id))
        }
    }

    let layer = CALayer()
    private let items: [Item]
    private let frames: [CGRect]
    private var hovered: Int?

    private static let height: CGFloat = 30
    private static let titleFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    private static let keyFont = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)

    init(items: [Item], scale: CGFloat) {
        self.items = items
        let widths = items.map { item in
            let title = (item.title as NSString).size(withAttributes: [.font: Self.titleFont]).width
            let key = (item.key as NSString).size(withAttributes: [.font: Self.keyFont]).width
            return ceil(8 + 14 + 5 + title + (item.key.isEmpty ? 0 : 5 + key) + 8)
        }
        frames = ActionBarLayout.items(widths: widths, height: Self.height)
        layer.bounds.size = CGSize(width: ActionBarLayout.width(of: widths), height: Self.height)
        layer.contentsScale = scale
        layer.isHidden = true
        render()
    }

    var size: CGSize { layer.bounds.size }

    func place(below hole: CGRect, in bounds: CGSize) {
        layer.frame = ActionBarLayout.frame(size: size, below: hole, in: bounds)
    }

    func contains(_ p: CGPoint) -> Bool { !layer.isHidden && layer.frame.contains(p) }

    /// The action under a view point, if the bar is showing there.
    func action(at p: CGPoint) -> CaptureAction? {
        index(at: p).map { items[$0].action }
    }

    func hover(at p: CGPoint?) {
        let index = p.flatMap(index(at:))
        guard index != hovered else { return }
        hovered = index
        render()
    }

    private func index(at p: CGPoint) -> Int? {
        guard contains(p) else { return nil }
        let local = CGPoint(x: p.x - layer.frame.minX, y: p.y - layer.frame.minY)
        return frames.firstIndex { $0.contains(local) }
    }

    /// Draws the whole bar into a bitmap at the display's scale.
    private func render() {
        let scale = layer.contentsScale
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return }
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer {
            NSGraphicsContext.restoreGraphicsState()
            layer.contents = bitmap.cgImage
        }
        NSColor(white: 0.08, alpha: 0.86).setFill()
        NSBezierPath(roundedRect: CGRect(origin: .zero, size: size), xRadius: 8, yRadius: 8).fill()
        for (index, (item, frame)) in zip(items, frames).enumerated() {
            if index == hovered {
                NSColor(white: 1, alpha: 0.18).setFill()
                NSBezierPath(roundedRect: frame, xRadius: 5, yRadius: 5).fill()
            }
            let iconRect = CGRect(x: frame.minX + 8, y: frame.midY - 7, width: 14, height: 14)
            if let icon = item.icon {
                icon.draw(in: iconRect)
            } else if let symbol = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.title)?
                .withSymbolConfiguration(.init(pointSize: 11, weight: .medium).applying(.init(paletteColors: [.white])))
            {
                let s = symbol.size
                symbol.draw(in: CGRect(x: iconRect.midX - s.width / 2, y: iconRect.midY - s.height / 2, width: s.width, height: s.height))
            }
            let title = NSAttributedString(string: item.title, attributes: [
                .font: Self.titleFont, .foregroundColor: NSColor.white,
            ])
            let titleSize = title.size()
            title.draw(at: CGPoint(x: iconRect.maxX + 5, y: frame.midY - titleSize.height / 2))
            if !item.key.isEmpty {
                let key = NSAttributedString(string: item.key, attributes: [
                    .font: Self.keyFont, .foregroundColor: NSColor(white: 1, alpha: 0.5),
                ])
                let keySize = key.size()
                key.draw(at: CGPoint(x: iconRect.maxX + 5 + titleSize.width + 5, y: frame.midY - keySize.height / 2))
            }
        }
    }
}
