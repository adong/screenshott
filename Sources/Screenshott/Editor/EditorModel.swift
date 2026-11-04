import AppKit
import ScreenshottCore

enum EditorTool: CaseIterable {
    case select, arrow, rectangle, ellipse, triangle, text, pixelate, crop

    /// Pressed on its own, with nothing being typed, it picks the tool.
    var key: String {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .rectangle: "r"
        case .ellipse: "o"
        case .triangle: "d"
        case .text: "t"
        case .pixelate: "m"
        case .crop: "c"
        }
    }

    var title: String {
        switch self {
        case .select: "Select"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .ellipse: "Oval"
        case .triangle: "Triangle"
        case .text: "Text"
        case .pixelate: "Pixelate"
        case .crop: "Crop"
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .triangle: "triangle"
        case .text: "textformat"
        case .pixelate: "checkerboard.rectangle"
        case .crop: "crop"
        }
    }

    /// What a drag on empty canvas draws.
    var kind: Annotation.Kind? {
        switch self {
        case .arrow: .arrow
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .triangle: .triangle
        case .text: .text
        case .pixelate: .pixelate
        case .select, .crop: nil
        }
    }
}

/// The S / M / L control: line widths and font sizes in points, so a 2x capture gets
/// lines twice as many pixels wide and they look the same on screen.
enum StrokeSize: Int, CaseIterable {
    case small, medium, large

    var lineWidth: Double { [2, 4, 8][rawValue] }
    var fontSize: Double { [14, 20, 32][rawValue] }
    var title: String { ["S", "M", "L"][rawValue] }
}

/// One editor window's state: the document, its captures' pixels, the current tool
/// and style, and undo. The canvas and toolbar read it and call back into it.
@MainActor
final class EditorModel {
    private(set) var document: EditorDocument
    /// Every capture this editor has held, by id. Kept after an undo takes one off the
    /// canvas, so redo can put it back.
    private(set) var images: [UUID: CGImage]
    let undoManager = UndoManager()

    var tool = EditorTool.arrow { didSet { changed() } }
    var color = RGBAColor.palette[0] { didSet { changed() } }
    var stroke = StrokeSize.medium { didSet { changed() } }
    var cover = Annotation.Cover.mosaic { didSet { changed() } }
    var selection: UUID? { didSet { if selection != oldValue { changed() } } }
    /// A capture picked with the select tool, so Delete can take it off a combined
    /// canvas. Never set together with `selection`.
    var selectedImage: UUID? { didSet { if selectedImage != oldValue { changed() } } }

    /// What the canvas and toolbar do when anything here changes.
    var onChange: (() -> Void)?

    /// The document as last saved; anything else is unsaved.
    private var saved: EditorDocument

    init(document: EditorDocument, images: [UUID: CGImage]) {
        self.document = document
        self.images = images
        saved = document
        undoManager.levelsOfUndo = 100
    }

    var isDirty: Bool { document != saved }

    func markSaved() {
        saved = document
        changed()
    }

    var selectedAnnotation: Annotation? { selection.flatMap(document.annotation) }

    /// Shows `document` without an undo step — the live state during a drag.
    func show(_ document: EditorDocument) {
        self.document = document
        changed()
    }

    /// Ends a drag or any other edit that started at `before`: one undo step named
    /// `name`, if anything actually changed.
    func commit(_ name: String, from before: EditorDocument) {
        guard document != before else { return changed() }
        registerUndo(restoring: before, name: name)
        changed()
    }

    func edit(_ name: String, _ change: (inout EditorDocument) -> Void) {
        let before = document
        change(&document)
        commit(name, from: before)
    }

    func addImage(_ image: CGImage, id: UUID) {
        images[id] = image
    }

    /// Style for a new annotation of `kind`, from the toolbar.
    func size(for kind: Annotation.Kind) -> Double {
        (kind == .text ? stroke.fontSize : stroke.lineWidth) * document.scale
    }

    // Toolbar picks set the style for what comes next and restyle the selection.

    func pick(color: RGBAColor) {
        self.color = color
        restyleSelection("Color") { $0.color = color }
    }

    func pick(stroke: StrokeSize) {
        self.stroke = stroke
        restyleSelection("Size") { [self] in $0.size = size(for: $0.kind) }
    }

    func pick(cover: Annotation.Cover) {
        self.cover = cover
        restyleSelection("Pixelate Style") { if $0.kind == .pixelate { $0.cover = cover } }
    }

    private func restyleSelection(_ name: String, _ change: (inout Annotation) -> Void) {
        guard var annotation = selectedAnnotation else { return }
        change(&annotation)
        edit(name) { $0.update(annotation) }
    }

    /// Each undo registers its own redo, so both directions are the same snapshot swap.
    private func registerUndo(restoring snapshot: EditorDocument, name: String) {
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                let current = model.document
                model.document = snapshot
                model.registerUndo(restoring: current, name: name)
                if let selection = model.selection, snapshot.annotation(selection) == nil { model.selection = nil }
                if let image = model.selectedImage, snapshot.image(image) == nil { model.selectedImage = nil }
                model.changed()
            }
        }
        undoManager.setActionName(name)
    }

    private func changed() {
        onChange?()
    }
}

extension RGBAColor {
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}
