import AppKit
import Carbon.HIToolbox
import ScreenshottCore

/// Live Area: a clear panel over every display, and the screen keeps moving under it.
/// Drag a rectangle and letting go takes it; a click takes the window under the
/// pointer; Esc or a right-click cancels.
///
/// Screenshott stays in the background, so the app being captured keeps its active
/// look. The price is the pointer: only the frontmost app can make it a crosshair, so
/// guide lines through the pointer stand in for one.
@MainActor
final class LiveAreaPicker {
    private var panels: [NSPanel] = []
    private let onFinish: (CGRect?) -> Void
    private var finished = false

    /// `windows` in global CoreGraphics points, front to back, as `WindowList` reports
    /// them. `onFinish` gets the area in Cocoa global points, or nil when cancelled.
    init(windows: [CGRect], onFinish: @escaping (CGRect?) -> Void) {
        self.onFinish = onFinish
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let cocoaWindows = windows.map { GlobalCoordinates.cocoaRect(fromCG: $0, mainScreenHeight: mainHeight) }
        for screen in NSScreen.screens {
            let panel = OverlayPanel(
                contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
            )
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.acceptsMouseMovedEvents = true
            panel.animationBehavior = .none
            panel.contentView = LiveAreaView(screen: screen, windows: cocoaWindows, picker: self)
            panels.append(panel)
        }
    }

    func show() {
        for panel in panels {
            panel.setFrame(panel.screen?.frame ?? panel.frame, display: false)
            panel.orderFrontRegardless()
        }
        // Key without activating the app, so Esc arrives and the target app stays active.
        let pointer = NSEvent.mouseLocation
        let panel = panels.first { $0.frame.contains(pointer) } ?? panels.first
        panel?.makeKey()
        if let view = panel?.contentView { _ = panel?.makeFirstResponder(view) }
        for panel in panels { (panel.contentView as? LiveAreaView)?.pointerMoved(toScreen: pointer) }
    }

    func cancel() { finish(nil) }

    fileprivate func pointerMoved(toScreen p: CGPoint) {
        for panel in panels { (panel.contentView as? LiveAreaView)?.pointerMoved(toScreen: p) }
    }

    fileprivate func finish(_ area: CGRect?) {
        guard !finished else { return }
        finished = true
        for panel in panels { panel.orderOut(nil) }
        onFinish(area.flatMap { $0.width >= 1 && $0.height >= 1 ? $0 : nil })
    }
}

/// One display's clear layer: guide lines through the pointer, a faint dim outside the
/// rectangle being dragged, and its size in pixels.
@MainActor
private final class LiveAreaView: NSView {
    private let screen: NSScreen
    private let windows: [CGRect]
    private weak var picker: LiveAreaPicker?
    private var start: CGPoint?
    private var current: CGPoint?
    private var pointer: CGPoint?
    private var dragged = false

    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let guidesLayer = CAShapeLayer()
    private let sizeLayer = CATextLayer()

    init(screen: NSScreen, windows: [CGRect], picker: LiveAreaPicker) {
        self.screen = screen
        self.windows = windows
        self.picker = picker
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
        layer = CALayer()
        wantsLayer = true
        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.25).cgColor
        dimLayer.fillRule = .evenOdd
        borderLayer.fillColor = nil
        borderLayer.strokeColor = NSColor.white.cgColor
        borderLayer.lineWidth = 1
        borderLayer.shadowColor = NSColor.black.cgColor
        borderLayer.shadowOpacity = 0.6
        borderLayer.shadowRadius = 1
        borderLayer.shadowOffset = .zero
        guidesLayer.strokeColor = NSColor.white.withAlphaComponent(0.8).cgColor
        guidesLayer.lineWidth = 1
        guidesLayer.lineDashPattern = [4, 3]
        guidesLayer.shadowColor = NSColor.black.cgColor
        guidesLayer.shadowOpacity = 0.7
        guidesLayer.shadowRadius = 0.5
        guidesLayer.shadowOffset = .zero
        sizeLayer.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        sizeLayer.fontSize = 11
        sizeLayer.foregroundColor = NSColor.white.cgColor
        sizeLayer.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        sizeLayer.cornerRadius = 4
        sizeLayer.alignmentMode = .center
        sizeLayer.contentsScale = screen.backingScaleFactor
        for sublayer in [dimLayer, borderLayer, guidesLayer, sizeLayer] { layer?.addSublayer(sublayer) }
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

    func pointerMoved(toScreen p: CGPoint) {
        let local = CGPoint(x: p.x - screen.frame.minX, y: p.y - screen.frame.minY)
        pointer = bounds.contains(local) ? local : nil
        refresh()
    }

    override func mouseMoved(with event: NSEvent) { picker?.pointerMoved(toScreen: screenPoint(event)) }

    override func mouseDown(with event: NSEvent) {
        start = clamped(localPoint(event))
        current = start
        dragged = false
        refresh()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let p = clamped(localPoint(event))
        if hypot(p.x - start.x, p.y - start.y) > 3 { dragged = true }
        current = p
        picker?.pointerMoved(toScreen: screenPoint(event))
    }

    override func mouseUp(with event: NSEvent) {
        let origin = screen.frame.origin
        if dragged, let rect = selection {
            picker?.finish(rect.offsetBy(dx: origin.x, dy: origin.y))
        } else {
            // A click takes the window under the pointer, cut to this display.
            let p = screenPoint(event)
            if let window = windows.first(where: { $0.contains(p) })?.intersection(screen.frame), !window.isEmpty {
                picker?.finish(window)
            } else {
                start = nil
                refresh()
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) { picker?.cancel() }

    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape { picker?.cancel() } else { super.keyDown(with: event) }
    }

    /// The dragged rectangle in view points, snapped to whole pixels.
    private var selection: CGRect? {
        guard let start, let current, dragged else { return nil }
        let scale = screen.backingScaleFactor
        func snap(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
        let x0 = snap(min(start.x, current.x)), x1 = snap(max(start.x, current.x))
        let y0 = snap(min(start.y, current.y)), y1 = snap(max(start.y, current.y))
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    private func refresh() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        if let rect = selection {
            let dim = CGMutablePath()
            dim.addRect(bounds)
            dim.addRect(rect)
            dimLayer.path = dim
            borderLayer.path = CGPath(rect: rect.insetBy(dx: -0.5, dy: -0.5), transform: nil)
            let scale = screen.backingScaleFactor
            sizeLayer.string = "\(Int((rect.width * scale).rounded())) × \(Int((rect.height * scale).rounded()))"
            let size = CGSize(width: 96, height: 18)
            let above = rect.maxY + 6 + size.height <= bounds.height
            sizeLayer.frame = CGRect(
                x: min(max(rect.minX, 0), bounds.width - size.width),
                y: above ? rect.maxY + 6 : max(rect.maxY - 6 - size.height, 0),
                width: size.width, height: size.height
            )
            sizeLayer.isHidden = false
        } else {
            dimLayer.path = nil
            borderLayer.path = nil
            sizeLayer.isHidden = true
        }

        if let pointer {
            let guides = CGMutablePath()
            guides.move(to: CGPoint(x: 0, y: pointer.y.rounded() + 0.5))
            guides.addLine(to: CGPoint(x: bounds.width, y: pointer.y.rounded() + 0.5))
            guides.move(to: CGPoint(x: pointer.x.rounded() + 0.5, y: 0))
            guides.addLine(to: CGPoint(x: pointer.x.rounded() + 0.5, y: bounds.height))
            guidesLayer.path = guides
        } else {
            guidesLayer.path = nil
        }
    }

    private func clamped(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), bounds.width), y: min(max(p.y, 0), bounds.height))
    }

    private func localPoint(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    private func screenPoint(_ event: NSEvent) -> CGPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }
}
