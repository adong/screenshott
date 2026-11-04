import AppKit
import ScreenshottCore

/// One display's overlay for a scrolling capture. Unlike the area overlay the screen
/// stays live: this view draws only the dimming outside the selection, its border,
/// handles and size label, plus a hint and the Auto-scroll / Scroll Myself buttons.
/// While capturing it lets every click and scroll through to the app underneath.
@MainActor
final class ScrollSelectionView: NSView {
    let screen: NSScreen
    let geometry: OverlayGeometry
    /// Other apps' windows in this display's pixels, front to back.
    private let windows: [(rect: PixelRect, target: ScrollTarget)]
    private weak var controller: ScrollingCapture?

    private var model: SelectionModel
    private var hover: PixelRect?
    private var pointer: CGPoint?
    private var pressHit: SelectionModel.Hit = .outside
    /// The mouse is down: the buttons hide until it's up.
    private var pressing = false
    private var capturing = false

    private let drawing = DrawingView()
    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let handlesLayer = CAShapeLayer()
    private let sizeLabel: TagLayer
    private let hint: TagLayer
    private let bar: NSView
    private let note = NSTextField(labelWithString: "")

    var hasSelection: Bool { model.selection != nil }
    var selection: PixelRect? { model.selection }

    private var tolerance: Int { Int((6 * geometry.scale).rounded()) }

    init(screen: NSScreen, windows: [ScrollTarget], controller: ScrollingCapture) {
        self.screen = screen
        let scale = screen.backingScaleFactor
        geometry = OverlayGeometry(
            pointSize: screen.frame.size,
            pixelSize: PixelSize(
                width: Int((screen.frame.width * scale).rounded()), height: Int((screen.frame.height * scale).rounded())
            )
        )
        let displayBounds = screen.displayID.map(CGDisplayBounds) ?? .zero
        self.windows = windows.compactMap { [geometry] target in
            geometry.pixelRect(forGlobal: target.bounds, displayBounds: displayBounds).map { ($0, target) }
        }
        self.controller = controller
        model = SelectionModel(bounds: geometry.pixelSize, clickSlop: Int((3 * scale).rounded()))
        sizeLabel = TagLayer(scale: scale, size: 11)
        hint = TagLayer(scale: scale, size: 13)
        bar = Self.makeBar()
        super.init(frame: CGRect(origin: .zero, size: geometry.pointSize))

        drawing.frame = bounds
        drawing.autoresizingMask = [.width, .height]
        let root = CALayer()
        drawing.layer = root
        drawing.wantsLayer = true
        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.35).cgColor
        dimLayer.fillRule = .evenOdd
        borderLayer.fillColor = nil
        borderLayer.lineWidth = 1
        borderLayer.shadowColor = NSColor.black.cgColor
        borderLayer.shadowOpacity = 0.6
        borderLayer.shadowRadius = 1
        borderLayer.shadowOffset = .zero
        handlesLayer.fillColor = NSColor.white.cgColor
        handlesLayer.strokeColor = NSColor.black.withAlphaComponent(0.4).cgColor
        handlesLayer.lineWidth = 0.5
        for sublayer in [dimLayer, borderLayer, handlesLayer, sizeLabel.layer, hint.layer] { root.addSublayer(sublayer) }
        addSubview(drawing)
        hint.set("Drag over the part that scrolls, or click a scroll area · Esc cancels")
        hint.place(at: CGPoint(x: (bounds.width - hint.layer.bounds.width) / 2, y: bounds.height - 90))

        note.font = .systemFont(ofSize: 11)
        note.textColor = .systemOrange
        note.isHidden = true
        bar.isHidden = true
        addSubview(bar)
        addSubview(note)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    // MARK: - Controller

    func pointerMoved(toScreen p: CGPoint?) {
        let origin = screen.frame.origin
        pointer = p.map { CGPoint(x: $0.x - origin.x, y: $0.y - origin.y) }
        updateHover()
        updateCursor()
        refresh()
    }

    func clearSelection() {
        guard model.selection != nil else { return }
        model.selection = nil
        refresh()
    }

    func nudgeSelection(dx: Int, dy: Int) {
        model.nudge(dx: dx, dy: dy)
        refresh()
    }

    func resizeSelection(dx: Int, dy: Int) {
        model.resize(dx: dx, dy: dy)
        refresh()
    }

    func stage(selection: PixelRect) {
        model.selection = selection.clamped(to: geometry.pixelSize)
        refresh()
    }

    /// Shown under the buttons — e.g. why auto-scroll isn't available.
    func show(note text: String) {
        note.stringValue = text
        note.isHidden = text.isEmpty
        refresh()
    }

    /// From here on the overlay only frames the region; the app underneath gets the input.
    func enterCapture() {
        capturing = true
        hover = nil
        refresh()
    }

    // MARK: - Events

    override func mouseMoved(with event: NSEvent) {
        controller?.pointerMoved(toScreen: screenPoint(event))
    }

    override func mouseDown(with event: NSEvent) {
        controller?.pressBegan(in: self)
        let edge = geometry.edge(at: localPoint(event))
        if event.clickCount == 2, model.hit(edge, tolerance: tolerance) == .inside {
            controller?.startCapture(.auto)
            return
        }
        pressHit = model.begin(at: edge, tolerance: tolerance)
        pressing = true
        refresh()
    }

    override func mouseDragged(with event: NSEvent) {
        model.drag(to: geometry.edge(at: localPoint(event)))
        controller?.pointerMoved(toScreen: screenPoint(event))
    }

    override func mouseUp(with event: NSEvent) {
        pressing = false
        if model.end(), pressHit == .outside {
            // A click takes the scroll area under the pointer, else its window.
            let pixel = geometry.pixel(at: localPoint(event))
            if let window = windows.first(where: { $0.rect.contains(pixel) }) {
                let global = screenPoint(event)
                let mainHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
                let point = GlobalCoordinates.cgPoint(fromCocoa: global, mainScreenHeight: mainHeight)
                let displayBounds = screen.displayID.map(CGDisplayBounds) ?? .zero
                model.selection = ScrollTargets.scrollArea(at: point, pid: window.target.pid)
                    .flatMap { geometry.pixelRect(forGlobal: $0, displayBounds: displayBounds) }
                    .flatMap { $0.clamped(to: geometry.pixelSize) } ?? window.rect
            } else {
                model.selection = nil
            }
        }
        controller?.pointerMoved(toScreen: screenPoint(event))
    }

    override func keyDown(with event: NSEvent) {
        if controller?.handleKey(event) != true { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return false }
        return controller?.handleKey(event) ?? false
    }

    // MARK: - Drawing

    private func updateHover() {
        guard let pointer, !capturing, controller?.selectionView == nil else {
            hover = nil
            return
        }
        let pixel = geometry.pixel(at: pointer)
        hover = windows.first { $0.rect.contains(pixel) }?.rect
    }

    private func updateCursor() {
        guard let pointer, !capturing else { return }
        let cursor: NSCursor
        if model.isMoving {
            cursor = .closedHand
        } else {
            switch model.hit(geometry.edge(at: pointer), tolerance: tolerance) {
            case .inside: cursor = .openHand
            case .handle(.left), .handle(.right): cursor = .resizeLeftRight
            case .handle(.top), .handle(.bottom): cursor = .resizeUpDown
            default: cursor = .crosshair
            }
        }
        cursor.set()
    }

    private func refresh() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let selected = model.selection != nil
        let hole = (model.selection ?? hover).map(geometry.viewRect(for:))
        let dim = CGMutablePath()
        dim.addRect(bounds)
        if let hole { dim.addRect(hole) }
        dimLayer.path = dim
        hint.layer.isHidden = capturing || selected

        if let hole, let target = model.selection ?? hover {
            borderLayer.path = CGPath(rect: hole.insetBy(dx: -0.5, dy: -0.5), transform: nil)
            borderLayer.lineWidth = capturing ? 2 : 1
            borderLayer.strokeColor = capturing
                ? NSColor.systemRed.cgColor : NSColor.white.withAlphaComponent(selected ? 1 : 0.7).cgColor
            if capturing {
                borderLayer.path = CGPath(rect: hole.insetBy(dx: -1, dy: -1), transform: nil)
                sizeLabel.layer.isHidden = true
            } else {
                sizeLabel.set("\(target.width) × \(target.height)")
                let size = sizeLabel.layer.bounds.size
                let above = hole.maxY + 6 + size.height <= bounds.height
                sizeLabel.place(at: CGPoint(
                    x: min(max(hole.minX, 0), bounds.width - size.width),
                    y: above ? hole.maxY + 6 : max(hole.maxY - 6 - size.height, 0)
                ))
                sizeLabel.layer.isHidden = false
            }
        } else {
            borderLayer.path = nil
            sizeLabel.layer.isHidden = true
        }
        handlesLayer.path = selected && !capturing ? hole.flatMap(handlesPath(for:)) : nil
        placeBar(below: selected && !capturing && !pressing ? hole : nil)
    }

    /// The buttons sit under the selection, or above it, or inside its bottom edge.
    private func placeBar(below hole: CGRect?) {
        guard let hole else {
            bar.isHidden = true
            note.isHidden = true
            return
        }
        let size = bar.fittingSize
        var y = hole.minY - 10 - size.height
        if y < 8 { y = hole.maxY + 34 }
        if y + size.height > bounds.height - 8 { y = hole.minY + 10 }
        let x = min(max(hole.midX - size.width / 2, 8), bounds.width - size.width - 8)
        bar.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
        bar.isHidden = false
        note.sizeToFit()
        note.frame.origin = CGPoint(x: min(max(hole.midX - note.frame.width / 2, 8), bounds.width - note.frame.width - 8), y: y - note.frame.height - 4)
        note.isHidden = note.stringValue.isEmpty
    }

    private func handlesPath(for rect: CGRect) -> CGPath? {
        guard rect.width >= 24, rect.height >= 24 else { return nil }
        let path = CGMutablePath()
        for x in [rect.minX, rect.midX, rect.maxX] {
            for y in [rect.minY, rect.midY, rect.maxY] where !(x == rect.midX && y == rect.midY) {
                path.addRect(CGRect(x: x - 3, y: y - 3, width: 6, height: 6))
            }
        }
        return path
    }

    private static func makeBar() -> NSView {
        let effect = ButtonBar()
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .withinWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 8
        effect.appearance = NSAppearance(named: .darkAqua)
        let auto = NSButton(title: "Auto-scroll  ↩", target: nil, action: #selector(ScrollingCapture.autoClicked))
        let manual = NSButton(title: "Scroll Myself  M", target: nil, action: #selector(ScrollingCapture.manualClicked))
        for button in [auto, manual] {
            button.bezelStyle = .rounded
            button.controlSize = .large
        }
        auto.keyEquivalent = ""
        let stack = NSStackView(views: [auto, manual])
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        return effect
    }

    /// The buttons' target, set once the controller exists.
    func connectButtons(to target: ScrollingCapture) {
        for case let button as NSButton in (bar.subviews.first as? NSStackView)?.arrangedSubviews ?? [] {
            button.target = target
        }
    }

    private func localPoint(_ event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    private func screenPoint(_ event: NSEvent) -> CGPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }
}

/// Swallows presses between the buttons, which would otherwise reach the view below and
/// start a new selection.
private final class ButtonBar: NSVisualEffectView {
    override func mouseDown(with event: NSEvent) {}
}

/// Layer-hosting, under the buttons, and transparent to the mouse so the selection view
/// above it in the event chain gets every press.
private final class DrawingView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// White text on a dark rounded tag.
@MainActor
final class TagLayer {
    let layer = CALayer()
    private let text = CATextLayer()
    private let font: NSFont

    init(scale: CGFloat, size: CGFloat) {
        font = .systemFont(ofSize: size, weight: .medium)
        layer.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        layer.cornerRadius = 5
        text.font = font
        text.fontSize = size
        text.foregroundColor = NSColor.white.cgColor
        text.contentsScale = scale
        layer.addSublayer(text)
    }

    func set(_ string: String) {
        let size = NSAttributedString(string: string, attributes: [.font: font]).size()
        let width = ceil(size.width), height = ceil(size.height)
        let pad = (font.pointSize / 2).rounded()
        text.string = string
        text.frame = CGRect(x: pad, y: pad / 2, width: width, height: height)
        layer.bounds.size = CGSize(width: width + 2 * pad, height: height + pad)
    }

    func place(at origin: CGPoint) {
        layer.frame = CGRect(origin: origin, size: layer.bounds.size)
    }
}
