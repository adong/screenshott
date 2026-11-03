import AppKit
import ScreenshottCore

/// One display's frozen overlay: the captured frame, dimmed outside the selection (or
/// the window under the pointer), with a size label and a pixel loupe. Layer-hosting
/// and non-flipped, so layer frames are view points with a bottom-left origin.
@MainActor
final class OverlayView: NSView {
    let display: FrozenDisplay
    let geometry: OverlayGeometry
    /// Snap targets in this display's pixels, front to back.
    private let windows: [PixelRect]
    private weak var controller: OverlayController?

    private var model: SelectionModel
    private var hover: PixelRect?
    /// The pointer in view points; nil while it is on another display.
    private var pointer: CGPoint?
    private var pressHit: SelectionModel.Hit = .outside

    private let imageLayer = CALayer()
    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let handlesLayer = CAShapeLayer()
    private let sizeLabel: Label
    private let loupe: Loupe

    var hasSelection: Bool { model.selection != nil }
    /// What Enter captures: the selection, else the window under the pointer.
    var target: PixelRect? { model.selection ?? hover }

    /// Handle grab distance and click slop, in this display's pixels.
    private var tolerance: Int { Int((6 * geometry.scale).rounded()) }

    init(display: FrozenDisplay, windows: [PixelRect], controller: OverlayController) {
        self.display = display
        geometry = display.geometry
        self.windows = windows
        self.controller = controller
        model = SelectionModel(bounds: geometry.pixelSize, clickSlop: Int((3 * geometry.scale).rounded()))
        sizeLabel = Label(scale: geometry.scale)
        loupe = Loupe(scale: geometry.scale)
        super.init(frame: CGRect(origin: .zero, size: geometry.pointSize))

        layer = CALayer()
        wantsLayer = true
        imageLayer.contents = display.image
        imageLayer.contentsGravity = .resize
        imageLayer.frame = bounds
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
        for sublayer in [imageLayer, dimLayer, borderLayer, handlesLayer, sizeLabel.layer, loupe.layer] {
            layer?.addSublayer(sublayer)
        }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self
        ))
    }

    // MARK: - Controller

    /// `p` in Cocoa global points, or nil when the pointer is on another display.
    func pointerMoved(toScreen p: CGPoint?) {
        let origin = display.screen.frame.origin
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

    /// Sets a selection without a mouse — for the README shots.
    func stage(selection: PixelRect) {
        model.selection = selection.clamped(to: geometry.pixelSize)
        refresh()
    }

    // MARK: - Events

    override func mouseMoved(with event: NSEvent) {
        controller?.pointerMoved(toScreen: screenPoint(event))
    }

    override func mouseDown(with event: NSEvent) {
        controller?.pressBegan(in: self)
        let edge = geometry.edge(at: localPoint(event))
        if event.clickCount == 2, model.hit(edge, tolerance: tolerance) == .inside, let controller {
            controller.confirm(controller.enterAction)
            return
        }
        pressHit = model.begin(at: edge, tolerance: tolerance)
        refresh()
    }

    override func mouseDragged(with event: NSEvent) {
        model.drag(to: geometry.edge(at: localPoint(event)))
        controller?.pointerMoved(toScreen: screenPoint(event))
    }

    override func mouseUp(with event: NSEvent) {
        if model.end(), pressHit == .outside {
            // A click takes the window under the pointer; on the desktop it clears.
            let pixel = geometry.pixel(at: localPoint(event))
            model.selection = windows.first { $0.contains(pixel) }
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
        // Only offer a window while nothing is selected on any display.
        guard let pointer, controller?.selectionView == nil else {
            hover = nil
            return
        }
        let pixel = geometry.pixel(at: pointer)
        hover = windows.first { $0.contains(pixel) }
    }

    private func updateCursor() {
        guard let pointer else { return }
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
        let hole = target.map(geometry.viewRect(for:))
        let dim = CGMutablePath()
        dim.addRect(bounds)
        if let hole { dim.addRect(hole) }
        dimLayer.path = dim

        if let hole, let target {
            // Outside the hole, so the line never covers a captured pixel.
            borderLayer.path = CGPath(rect: hole.insetBy(dx: -0.5, dy: -0.5), transform: nil)
            borderLayer.strokeColor = NSColor.white.withAlphaComponent(selected ? 1 : 0.7).cgColor
            sizeLabel.set("\(target.width) × \(target.height)")
            let size = sizeLabel.layer.bounds.size
            let above = hole.maxY + 6 + size.height <= bounds.height
            sizeLabel.place(at: CGPoint(
                x: min(max(hole.minX, 0), bounds.width - size.width),
                y: above ? hole.maxY + 6 : max(hole.maxY - 6 - size.height, 0)
            ))
            sizeLabel.layer.isHidden = false
        } else {
            borderLayer.path = nil
            sizeLabel.layer.isHidden = true
        }

        handlesLayer.path = selected ? hole.flatMap { handlesPath(for: $0) } : nil

        if let pointer, !model.isMoving {
            loupe.update(image: display.image, center: geometry.pixel(at: pointer), bounds: geometry.pixelSize)
            loupe.layer.frame = MagnifierLayout.frame(size: loupe.size, cursor: pointer, in: bounds.size)
            loupe.layer.isHidden = false
        } else {
            loupe.layer.isHidden = true
        }
    }

    /// Knobs on the corners and edge midpoints, once the selection is big enough that
    /// they don't crowd it.
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

    private func localPoint(_ event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    private func screenPoint(_ event: NSEvent) -> CGPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }
}

/// White text on a dark rounded tag.
@MainActor
private final class Label {
    let layer = CALayer()
    private let text = CATextLayer()
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

    init(scale: CGFloat) {
        layer.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        layer.cornerRadius = 4
        text.font = Self.font
        text.fontSize = Self.font.pointSize
        text.foregroundColor = NSColor.white.cgColor
        text.contentsScale = scale
        layer.addSublayer(text)
    }

    func set(_ string: String) {
        let size = NSAttributedString(string: string, attributes: [.font: Self.font]).size()
        let width = ceil(size.width), height = ceil(size.height)
        text.string = string
        text.frame = CGRect(x: 6, y: 3, width: width, height: height)
        layer.bounds.size = CGSize(width: width + 12, height: height + 6)
    }

    func place(at origin: CGPoint) {
        layer.frame = CGRect(origin: origin, size: layer.bounds.size)
    }
}

/// The magnifier: `MagnifierLayout.side` pixels square, each drawn as a sharp cell, the
/// pixel under the pointer outlined, its coordinates underneath.
@MainActor
private final class Loupe {
    let layer = CALayer()
    let size: CGSize
    private let zoom = CALayer()
    private let marker = CAShapeLayer()
    private let label: Label
    private static let cell: CGFloat = 9

    init(scale: CGFloat) {
        let side = CGFloat(MagnifierLayout.side) * Self.cell
        label = Label(scale: scale)
        label.set("0000, 0000")
        let labelHeight = label.layer.bounds.height
        size = CGSize(width: side, height: side + 4 + labelHeight)

        zoom.frame = CGRect(x: 0, y: labelHeight + 4, width: side, height: side)
        zoom.magnificationFilter = .nearest
        zoom.contentsGravity = .resize
        zoom.backgroundColor = NSColor.black.cgColor
        zoom.borderColor = NSColor.white.cgColor
        zoom.borderWidth = 1.5
        zoom.cornerRadius = 4
        zoom.masksToBounds = true
        marker.fillColor = nil
        marker.strokeColor = NSColor.white.cgColor
        marker.lineWidth = 1
        marker.shadowColor = NSColor.black.cgColor
        marker.shadowOpacity = 0.8
        marker.shadowRadius = 1
        marker.shadowOffset = .zero
        zoom.addSublayer(marker)
        layer.addSublayer(zoom)
        layer.addSublayer(label.layer)
    }

    func update(image: CGImage, center: PixelPoint, bounds: PixelSize) {
        let (rect, mark) = MagnifierLayout.source(around: center, in: bounds)
        zoom.contents = image.cropping(to: rect.cgRect)
        let cellWidth = zoom.bounds.width / CGFloat(rect.width)
        let cellHeight = zoom.bounds.height / CGFloat(rect.height)
        marker.path = CGPath(rect: CGRect(
            x: CGFloat(mark.x) * cellWidth,
            y: zoom.bounds.height - CGFloat(mark.y + 1) * cellHeight,
            width: cellWidth, height: cellHeight
        ), transform: nil)
        label.set("\(center.x), \(center.y)")
        label.place(at: CGPoint(x: (size.width - label.layer.bounds.width) / 2, y: 0))
    }
}
