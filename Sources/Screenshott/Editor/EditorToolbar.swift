import AppKit
import ScreenshottCore

/// The strip under the editor's title bar: tools, pixelate style, color, size, then
/// Copy, Save and a well to drag the result out of. Mirrors the model on `update()`.
@MainActor
final class EditorToolbar: NSView {
    private let model: EditorModel
    private let tools: NSSegmentedControl
    private let covers: NSSegmentedControl
    private let strokes: NSSegmentedControl
    private var swatches: [SwatchButton] = []
    private let stack = NSStackView()
    let dragWell = DragWell()

    static let height: CGFloat = 40

    /// Copy and Save are sent up the responder chain, to the editor window controller.
    init(model: EditorModel) {
        self.model = model
        tools = NSSegmentedControl(labels: EditorTool.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
        covers = NSSegmentedControl(labels: ["Mosaic", "Solid"], trackingMode: .selectOne, target: nil, action: nil)
        strokes = NSSegmentedControl(labels: StrokeSize.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
        super.init(frame: CGRect(x: 0, y: 0, width: 800, height: Self.height))

        for (index, tool) in EditorTool.allCases.enumerated() {
            if let image = NSImage(systemSymbolName: tool.symbol, accessibilityDescription: tool.title) {
                tools.setImage(image, forSegment: index)
                tools.setLabel("", forSegment: index)
                tools.setWidth(32, forSegment: index)
            }
            tools.setToolTip("\(tool.title) (\(tool.key.uppercased()))", forSegment: index)
        }
        tools.target = self
        tools.action = #selector(pickTool)

        for (index, (symbol, tip)) in [
            ("checkerboard.rectangle", "Mosaic — blocks of average color"),
            ("rectangle.fill", "Solid — paints the area out; mosaic text can sometimes be recovered"),
        ].enumerated() {
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip) {
                covers.setImage(image, forSegment: index)
                covers.setImageScaling(.scaleProportionallyDown, forSegment: index)
            }
            covers.setToolTip("\(tip) (M toggles)", forSegment: index)
        }
        covers.target = self
        covers.action = #selector(pickCover)

        for (index, stroke) in StrokeSize.allCases.enumerated() {
            strokes.setToolTip("Line width and text size (\(index + 1))", forSegment: index)
            strokes.setWidth(26, forSegment: stroke.rawValue)
        }
        strokes.target = self
        strokes.action = #selector(pickStroke)

        let colors = NSStackView()
        colors.spacing = 4
        for color in RGBAColor.palette {
            let swatch = SwatchButton(color: color)
            swatch.target = self
            swatch.action = #selector(pickColor(_:))
            swatches.append(swatch)
            colors.addArrangedSubview(swatch)
        }

        let copy = Self.button(
            "doc.on.doc", "Copy", tip: "Copy the image (⌘C)",
            action: #selector(EditorWindowController.copy(_:))
        )
        let save = Self.button(
            "square.and.arrow.down", "Save", tip: "Save the PNG to the screenshots folder (⌘S)",
            action: #selector(EditorWindowController.saveDocument(_:))
        )

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        stack.setHuggingPriority(.defaultHigh, for: .vertical)
        for view in [tools, covers, colors, strokes, spacer, copy, save, dragWell] { stack.addArrangedSubview(view) }
        stack.frame = bounds
        stack.autoresizingMask = [.width, .height]
        addSubview(stack)
        update()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Extra controls (M4's Combine) go after the size control.
    func insert(_ views: [NSView]) {
        let index = stack.arrangedSubviews.firstIndex(of: strokes).map { $0 + 1 } ?? stack.arrangedSubviews.count
        for (offset, view) in views.enumerated() { stack.insertArrangedSubview(view, at: index + offset) }
    }

    func update() {
        tools.selectedSegment = EditorTool.allCases.firstIndex(of: model.tool) ?? -1
        let selected = model.selectedAnnotation
        let color = selected?.color ?? model.color
        for swatch in swatches { swatch.isChosen = swatch.color == color }
        let cover = selected?.kind == .pixelate ? selected?.cover ?? model.cover : model.cover
        covers.selectedSegment = cover == .mosaic ? 0 : 1
        covers.isHidden = !(model.tool == .pixelate || selected?.kind == .pixelate)
        strokes.selectedSegment = model.stroke.rawValue
    }

    @objc private func pickTool() { model.tool = EditorTool.allCases[tools.selectedSegment] }

    @objc private func pickCover() { model.pick(cover: covers.selectedSegment == 0 ? .mosaic : .solid) }

    @objc private func pickStroke() {
        if let stroke = StrokeSize(rawValue: strokes.selectedSegment) { model.pick(stroke: stroke) }
    }

    @objc private func pickColor(_ sender: SwatchButton) { model.pick(color: sender.color) }

    private static func button(_ symbol: String, _ title: String, tip: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: nil, action: action)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.bezelStyle = .rounded
        button.toolTip = tip
        return button
    }
}

/// A round color chip; the chosen one gets a ring.
@MainActor
final class SwatchButton: NSButton {
    let color: RGBAColor
    var isChosen = false { didSet { needsDisplay = true } }

    init(color: RGBAColor) {
        self.color = color
        super.init(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        isBordered = false
        title = ""
        setButtonType(.momentaryChange)
        widthAnchor.constraint(equalToConstant: 20).isActive = true
        heightAnchor.constraint(equalToConstant: 20).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let chip = NSBezierPath(ovalIn: bounds.insetBy(dx: 3.5, dy: 3.5))
        color.nsColor.setFill()
        chip.fill()
        NSColor.separatorColor.setStroke()
        chip.lineWidth = 1
        chip.stroke()
        if isChosen {
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
            ring.lineWidth = 1.5
            NSColor.controlAccentColor.setStroke()
            ring.stroke()
        }
    }
}

/// Drag this into Finder, Slack, Mail or a browser to drop the PNG. The drag saves
/// first, so the file it hands over is the archived one.
@MainActor
final class DragWell: NSView, NSDraggingSource {
    /// Saves and returns the PNG, with a small picture of it for the drag.
    var provide: (() -> (file: URL, image: NSImage)?)?
    private var pressPoint: CGPoint?

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 30, height: 28))
        toolTip = "Drag the image into another app"
        widthAnchor.constraint(equalToConstant: 30).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.setFill()
        box.fill()
        NSColor.separatorColor.setStroke()
        box.stroke()
        let symbol = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: "Drag out")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        if let symbol {
            let size = symbol.size
            symbol.draw(in: CGRect(
                x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height
            ))
        }
    }

    override func mouseDown(with event: NSEvent) { pressPoint = convert(event.locationInWindow, from: nil) }

    override func mouseDragged(with event: NSEvent) {
        guard let pressPoint else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard hypot(p.x - pressPoint.x, p.y - pressPoint.y) > 3 else { return }
        self.pressPoint = nil
        guard let (file, image) = provide?() else { return NSSound.beep() }
        let item = NSDraggingItem(pasteboardWriter: file as NSURL)
        let side: CGFloat = 96
        let fit = min(side / max(image.size.width, 1), side / max(image.size.height, 1), 1)
        let size = CGSize(width: image.size.width * fit, height: image.size.height * fit)
        item.setDraggingFrame(CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height), contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) { pressPoint = nil }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }
}
