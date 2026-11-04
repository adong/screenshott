import AppKit
import Carbon.HIToolbox
import ScreenshottCore

/// The editor's canvas. It draws through CanvasRenderer — the same code that writes
/// the PNG — and turns presses and keys into edits on the model. Flipped, so view
/// points count down from the top-left like canvas pixels; one point is `scale`
/// pixels. The NSScrollView around it zooms and pans.
@MainActor
final class CanvasView: NSView, NSTextViewDelegate, NSMenuItemValidation {
    private let model: EditorModel

    /// What the current press is doing.
    private enum Gesture {
        case creating(Annotation)
        case moving(Annotation, from: CGPoint)
        case reshaping(Annotation, part: Annotation.Part)
        case panning(from: CGPoint, origin: CGPoint)
        case cropping
    }
    private var gesture: Gesture?
    /// The document when the press began, for its undo step.
    private var before: EditorDocument?
    private var pressPoint = CGPoint.zero
    /// Set once the pointer leaves the click slop, so a click only selects.
    private var dragged = false

    /// The crop tool shows one capture whole, with its crop as a selection to adjust.
    private struct CropSession {
        let imageID: UUID
        let preview: EditorDocument
        var selection: SelectionModel
    }
    private var crop: CropSession?
    private var toolBeforeCrop = EditorTool.arrow

    private var textView: NSTextView?
    private var editing: (id: UUID, before: EditorDocument)?
    /// Typing gets its own undo, thrown away when the text is done.
    private let textUndo = UndoManager()

    private var spaceDown = false

    /// Mosaic tiles, kept until the pixelate or the captures under it change.
    private struct CoverKey: Equatable {
        let region: PixelRect
        let images: [CanvasImage]
    }
    private var covers: [UUID: (key: CoverKey, image: CGImage)] = [:]

    init(model: EditorModel) {
        self.model = model
        super.init(frame: .zero)
        updateSize()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var scale: CGFloat { model.document.scale }
    private var magnification: CGFloat { enclosingScrollView?.magnification ?? 1 }
    /// What is on screen: the document, or the capture being cropped.
    private var shown: EditorDocument { crop?.preview ?? model.document }
    /// Six screen points, in canvas pixels.
    private var tolerance: Double { 6 / magnification * scale }
    var isCropping: Bool { crop != nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self
        ))
    }

    /// The model changed: tool, style, selection or document.
    func modelChanged() {
        if model.tool != .crop {
            toolBeforeCrop = model.tool
            if crop != nil { crop = nil }
        } else if crop == nil, model.document.images.count == 1 {
            beginCrop(on: model.document.images[0].id)
        }
        if let editing, let textView, let annotation = model.document.annotation(editing.id) {
            textView.font = TextLayout.font(size: annotation.size / scale) as NSFont
            textView.textColor = annotation.color.nsColor
            textView.insertionPointColor = annotation.color.nsColor
            textView.frame = textFrame(annotation)
        }
        updateSize()
        needsDisplay = true
    }

    private func updateSize() {
        let size = shown.canvasSize
        let points = CGSize(width: CGFloat(size.width) / scale, height: CGFloat(size.height) / scale)
        if frame.size != points { setFrameSize(points) }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let document = shown
        context.saveGState()
        context.scaleBy(x: 1 / scale, y: 1 / scale)
        // Zoomed in, show sharp pixels; zoomed out, smooth them.
        context.interpolationQuality = magnification >= 1 ? .none : .high
        CanvasRenderer.draw(document, images: model.images, covers: covers(for: document), hiding: editing?.id, in: context)
        context.restoreGState()

        if let crop {
            drawCrop(crop, in: context)
        } else if let selected = model.selectedAnnotation, selected.id != editing?.id {
            drawSelection(selected, in: context)
        }
    }

    private func covers(for document: EditorDocument) -> [UUID: CGImage] {
        var kept: [UUID: (key: CoverKey, image: CGImage)] = [:]
        for annotation in document.annotations where annotation.kind == .pixelate && annotation.cover == .mosaic {
            guard let region = CanvasRenderer.pixelRegion(of: annotation, in: document) else { continue }
            let key = CoverKey(region: region, images: document.images)
            if let cached = covers[annotation.id], cached.key == key {
                kept[annotation.id] = cached
            } else if let tile = CanvasRenderer.cover(for: annotation, in: document, images: model.images) {
                kept[annotation.id] = (key, tile)
            }
        }
        covers = kept
        return kept.mapValues(\.image)
    }

    /// A dashed box and knobs, a constant size on screen whatever the zoom.
    private func drawSelection(_ annotation: Annotation, in context: CGContext) {
        let unit = 1 / magnification
        context.saveGState()
        defer { context.restoreGState() }
        context.setLineWidth(unit)
        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        if annotation.kind != .arrow {
            context.setLineDash(phase: 0, lengths: [4 * unit, 3 * unit])
            context.stroke(viewRect(annotation.bounds).insetBy(dx: -3 * unit, dy: -3 * unit))
            context.setLineDash(phase: 0, lengths: [])
        }
        for (_, point) in annotation.handles {
            let p = viewPoint(point)
            let knob = CGRect(x: p.x - 4 * unit, y: p.y - 4 * unit, width: 8 * unit, height: 8 * unit)
            context.setFillColor(NSColor.white.cgColor)
            context.fillEllipse(in: knob)
            context.strokeEllipse(in: knob)
        }
    }

    /// The overlay's look: dim outside the crop, a white border, knobs and the size.
    private func drawCrop(_ crop: CropSession, in context: CGContext) {
        guard let selection = crop.selection.selection else { return }
        let unit = 1 / magnification
        let hole = viewRect(selection.cgRect)
        context.saveGState()
        defer { context.restoreGState() }
        context.addRect(bounds)
        context.addRect(hole)
        context.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        context.fillPath(using: .evenOdd)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(unit)
        context.stroke(hole.insetBy(dx: -unit / 2, dy: -unit / 2))
        if hole.width >= 24 * unit, hole.height >= 24 * unit {
            context.setFillColor(NSColor.white.cgColor)
            for x in [hole.minX, hole.midX, hole.maxX] {
                for y in [hole.minY, hole.midY, hole.maxY] where !(x == hole.midX && y == hole.midY) {
                    context.fill(CGRect(x: x - 3 * unit, y: y - 3 * unit, width: 6 * unit, height: 6 * unit))
                }
            }
        }
        let label = "\(selection.width) × \(selection.height)   Return to crop · Esc to cancel" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11 * unit, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.72),
        ]
        let height = label.size(withAttributes: attributes).height
        let y = hole.minY - height - 4 * unit >= 0 ? hole.minY - height - 4 * unit : hole.minY + 4 * unit
        label.draw(at: CGPoint(x: max(hole.minX, 0) + 4 * unit, y: y), withAttributes: attributes)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        if textView != nil { endEditing() }
        window?.makeFirstResponder(self)
        let p = canvasPoint(event)
        pressPoint = p
        dragged = false
        before = model.document

        if spaceDown, let clip = enclosingScrollView?.contentView {
            gesture = .panning(from: event.locationInWindow, origin: clip.bounds.origin)
            NSCursor.closedHand.set()
            return
        }
        if model.tool == .crop {
            cropMouseDown(event, at: p)
            return
        }
        let document = model.document
        if let hit = document.hit(p, tolerance: tolerance, selected: model.selection),
           let annotation = document.annotation(hit.id) {
            model.selection = hit.id
            if event.clickCount == 2, annotation.kind == .text {
                gesture = nil
                beginEditing(annotation, before: document)
            } else {
                gesture = hit.part == .body ? .moving(annotation, from: p) : .reshaping(annotation, part: hit.part)
            }
            return
        }
        model.selection = nil
        guard let kind = model.tool.kind else {
            gesture = nil
            return
        }
        let created = Annotation(
            kind: kind, start: p, end: p, color: model.color, size: model.size(for: kind), cover: model.cover
        )
        if kind == .text {
            gesture = nil
            var next = document
            next.add(created)
            model.show(next)
            model.selection = created.id
            beginEditing(created, before: document)
        } else {
            gesture = .creating(created)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let gesture else { return }
        if case .panning(let from, let origin) = gesture {
            pan(from: from, origin: origin, to: event.locationInWindow)
            return
        }
        // Zoomed in, dragging past the edge scrolls the canvas along.
        autoscroll(with: event)
        let p = canvasPoint(event)
        if case .cropping = gesture {
            crop?.selection.drag(to: pixel(p))
            needsDisplay = true
            return
        }
        if !dragged {
            guard hypot(p.x - pressPoint.x, p.y - pressPoint.y) > tolerance / 2 else { return }
            dragged = true
        }
        guard var next = before else { return }
        let constrained = event.modifierFlags.contains(.shift)
        switch gesture {
        case .creating(let annotation):
            next.add(annotation.dragging(.end, to: p, constrained: constrained))
        case .moving(let annotation, let from):
            var dx = p.x - from.x, dy = p.y - from.y
            // ⇧ keeps the move horizontal or vertical.
            if constrained { if abs(dx) > abs(dy) { dy = 0 } else { dx = 0 } }
            next.update(annotation.moved(dx: dx, dy: dy))
        case .reshaping(let annotation, let part):
            next.update(annotation.dragging(part, to: p, constrained: constrained))
        case .panning, .cropping:
            return
        }
        model.show(next)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            gesture = nil
            before = nil
            updateCursor(at: canvasPoint(event))
        }
        guard let gesture, let before else { return }
        switch gesture {
        case .creating(let annotation):
            guard dragged, let created = model.document.annotation(annotation.id), !created.isNegligible else {
                model.show(before)
                return
            }
            model.commit("Add \(annotation.kind.rawValue.capitalized)", from: before)
            model.selection = created.id
        case .moving:
            model.commit("Move", from: before)
        case .reshaping:
            model.commit("Resize", from: before)
        case .cropping:
            _ = crop?.selection.end()
            needsDisplay = true
        case .panning:
            break
        }
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(at: canvasPoint(event))
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(at: canvasPoint(event))
    }

    private func updateCursor(at p: CGPoint) {
        let cursor: NSCursor
        if spaceDown {
            cursor = .openHand
        } else if let crop {
            switch crop.selection.hit(pixel(p), tolerance: Int(tolerance.rounded())) {
            case .inside: cursor = .openHand
            case .handle(.left), .handle(.right): cursor = .resizeLeftRight
            case .handle(.top), .handle(.bottom): cursor = .resizeUpDown
            default: cursor = .crosshair
            }
        } else if let hit = model.document.hit(p, tolerance: tolerance, selected: model.selection) {
            cursor = hit.part == .body ? .openHand : .crosshair
        } else {
            switch model.tool {
            case .select: cursor = .arrow
            case .text: cursor = .iBeam
            default: cursor = .crosshair
            }
        }
        cursor.set()
    }

    private func pan(from start: CGPoint, origin: CGPoint, to point: CGPoint) {
        guard let scrollView = enclosingScrollView else { return }
        let clip = scrollView.contentView
        let m = magnification
        let proposed = CGRect(
            x: origin.x - (point.x - start.x) / m, y: origin.y + (point.y - start.y) / m,
            width: clip.bounds.width, height: clip.bounds.height
        )
        clip.scroll(to: clip.constrainBoundsRect(proposed).origin)
        scrollView.reflectScrolledClipView(clip)
    }

    // MARK: - Keys

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch Int(event.keyCode) {
        case kVK_Escape:
            if crop != nil {
                cancelCrop()
            } else {
                model.selection = nil
            }
            return
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if crop != nil {
                applyCrop()
            } else if let selected = model.selectedAnnotation, selected.kind == .text {
                beginEditing(selected, before: model.document)
            }
            return
        case kVK_Delete, kVK_ForwardDelete:
            deleteSelection()
            return
        case kVK_Space:
            if !event.isARepeat {
                spaceDown = true
                NSCursor.openHand.set()
            }
            return
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow:
            arrow(Int(event.keyCode), flags: flags)
            return
        default:
            break
        }
        guard flags.isEmpty, let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.keyDown(with: event)
        }
        if let tool = EditorTool.allCases.first(where: { $0.key == key }) {
            // M again flips between mosaic and solid.
            if tool == .pixelate, model.tool == .pixelate {
                model.pick(cover: model.cover == .mosaic ? .solid : .mosaic)
            } else {
                model.tool = tool
            }
        } else if let digit = Int(key), let stroke = StrokeSize(rawValue: digit - 1) {
            model.pick(stroke: stroke)
        } else {
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Space {
            spaceDown = false
            updateCursor(at: canvasPoint(inWindow: window?.mouseLocationOutsideOfEventStream ?? .zero))
        } else {
            super.keyUp(with: event)
        }
    }

    /// Moves the selection one pixel (⇧: ten). While cropping, ⌥ moves the crop's
    /// right and bottom edges instead, like the overlay.
    private func arrow(_ keyCode: Int, flags: NSEvent.ModifierFlags) {
        let step = flags.contains(.shift) ? 10 : 1
        let (dx, dy) = switch keyCode {
        case kVK_LeftArrow: (-step, 0)
        case kVK_RightArrow: (step, 0)
        case kVK_UpArrow: (0, -step)
        default: (0, step)
        }
        if crop != nil {
            if flags.contains(.option) { crop?.selection.resize(dx: dx, dy: dy) } else { crop?.selection.nudge(dx: dx, dy: dy) }
            needsDisplay = true
        } else if let selected = model.selectedAnnotation {
            model.edit("Move") { $0.update(selected.moved(dx: Double(dx), dy: Double(dy))) }
        }
    }

    private func deleteSelection() {
        guard crop == nil, let selected = model.selectedAnnotation else { return NSSound.beep() }
        model.selection = nil
        model.edit("Delete") { $0.remove(selected.id) }
    }

    // MARK: - Menu actions (ahead of NSWindow's own undo in the responder chain)

    private var activeUndoManager: UndoManager { textView != nil ? textUndo : model.undoManager }

    @objc func undo(_ sender: Any?) {
        if crop != nil { cancelCrop() }
        activeUndoManager.undo()
    }

    @objc func redo(_ sender: Any?) {
        if crop != nil { cancelCrop() }
        activeUndoManager.redo()
    }

    @objc func delete(_ sender: Any?) { deleteSelection() }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)):
            item.title = activeUndoManager.undoMenuItemTitle
            return activeUndoManager.canUndo
        case #selector(redo(_:)):
            item.title = activeUndoManager.redoMenuItemTitle
            return activeUndoManager.canRedo
        case #selector(delete(_:)):
            return model.selection != nil
        default:
            return true
        }
    }

    // MARK: - Text

    private func beginEditing(_ annotation: Annotation, before: EditorDocument) {
        editing = (annotation.id, before)
        let view = NSTextView(frame: textFrame(annotation))
        view.font = TextLayout.font(size: annotation.size / scale) as NSFont
        view.textColor = annotation.color.nsColor
        view.insertionPointColor = annotation.color.nsColor
        view.drawsBackground = false
        view.isRichText = false
        view.allowsUndo = true
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        view.isHorizontallyResizable = true
        view.isVerticallyResizable = true
        view.string = annotation.text
        view.delegate = self
        addSubview(view)
        textView = view
        window?.makeFirstResponder(view)
        view.selectAll(nil)
        needsDisplay = true
    }

    /// The text box, with room for the caret after the last character.
    private func textFrame(_ annotation: Annotation) -> CGRect {
        let size = TextLayout.size(of: annotation.text, fontSize: annotation.size)
        return CGRect(
            x: annotation.start.x / scale, y: annotation.start.y / scale,
            width: (size.width + annotation.size) / scale, height: size.height / scale
        )
    }

    func textDidChange(_ notification: Notification) {
        guard let textView, let editing, var annotation = model.document.annotation(editing.id) else { return }
        annotation.text = textView.string
        var next = model.document
        next.update(annotation)
        model.show(next)
    }

    /// Return finishes (⇧Return adds a line), like Esc or a click elsewhere.
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                textView.insertNewlineIgnoringFieldEditor(nil)
            } else {
                endEditing()
            }
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            endEditing()
            return true
        }
        return false
    }

    func undoManager(for view: NSTextView) -> UndoManager? { textUndo }

    /// Keeps the text as one undo step, or drops the annotation if it ended up empty.
    func endEditing() {
        guard let textView, let editing else { return }
        self.textView = nil
        self.editing = nil
        window?.makeFirstResponder(self)
        textView.removeFromSuperview()
        textUndo.removeAllActions()
        guard var annotation = model.document.annotation(editing.id) else { return }
        let isNew = editing.before.annotation(editing.id) == nil
        var next = model.document
        if annotation.isNegligible {
            next.remove(annotation.id)
            model.selection = nil
            model.show(next)
            model.commit("Delete Text", from: editing.before)
        } else {
            annotation.text = textView.string
            next.update(annotation)
            model.show(next)
            model.commit(isNew ? "Add Text" : "Edit Text", from: editing.before)
        }
    }

    // MARK: - Crop

    private func beginCrop(on id: UUID) {
        guard let image = model.document.image(id), let preview = model.document.uncropped(id) else { return }
        var selection = SelectionModel(bounds: image.pixelSize, clickSlop: Int((3 * scale).rounded()))
        selection.selection = image.crop
        crop = CropSession(imageID: id, preview: preview, selection: selection)
        model.selection = nil
        updateSize()
        needsDisplay = true
    }

    private func cropMouseDown(_ event: NSEvent, at p: CGPoint) {
        guard let session = crop else {
            // Several captures: the press picks which one to crop.
            if let image = model.document.image(at: p) { beginCrop(on: image.id) } else { NSSound.beep() }
            gesture = nil
            return
        }
        let tolerance = Int(self.tolerance.rounded())
        if event.clickCount == 2, session.selection.hit(pixel(p), tolerance: tolerance) == .inside {
            gesture = nil
            applyCrop()
            return
        }
        crop?.selection.begin(at: pixel(p), tolerance: tolerance)
        gesture = .cropping
    }

    func applyCrop() {
        guard let session = crop else { return }
        crop = nil
        model.tool = toolBeforeCrop
        if let rect = session.selection.selection, !rect.isEmpty {
            model.edit("Crop") { $0.crop(session.imageID, to: rect) }
        }
    }

    func cancelCrop() {
        guard crop != nil else { return }
        crop = nil
        model.tool = toolBeforeCrop
    }

    // MARK: - Coordinates

    private func canvasPoint(_ event: NSEvent) -> CGPoint {
        canvasPoint(inWindow: event.locationInWindow)
    }

    /// A window point in canvas pixels, rounded to whole pixels so shapes and
    /// pixelates line up with the capture's grid.
    private func canvasPoint(inWindow point: CGPoint) -> CGPoint {
        let p = convert(point, from: nil)
        return CGPoint(x: (p.x * scale).rounded(), y: (p.y * scale).rounded())
    }

    private func pixel(_ p: CGPoint) -> PixelPoint { PixelPoint(x: Int(p.x), y: Int(p.y)) }

    private func viewPoint(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x / scale, y: p.y / scale) }

    private func viewRect(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX / scale, y: r.minY / scale, width: r.width / scale, height: r.height / scale)
    }
}
