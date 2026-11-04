import AppKit
import ScreenshottCore

/// M4's part of the toolbar: Add Capture, and once there are two or more captures,
/// the automatic layout — column or row, alignment, gap (decision 3a).
@MainActor
final class CombineControls: NSStackView {
    private let model: EditorModel
    private let direction: NSSegmentedControl
    private let aligner: NSSegmentedControl
    private let gap = NSPopUpButton(frame: .zero, pullsDown: false)
    private static let gaps: [(title: String, points: Double)] = [("No gap", 0), ("4 pt", 4), ("16 pt", 16), ("32 pt", 32)]

    init(model: EditorModel) {
        self.model = model
        direction = NSSegmentedControl(labels: ["Column", "Row"], trackingMode: .selectOne, target: nil, action: nil)
        aligner = NSSegmentedControl(labels: ["Start", "Center", "End"], trackingMode: .selectOne, target: nil, action: nil)
        super.init(frame: .zero)
        spacing = 6

        // Up the responder chain to the editor window controller.
        let add = NSButton(title: "Add Capture", target: nil, action: #selector(EditorWindowController.addCapture(_:)))
        add.image = NSImage(systemSymbolName: "plus.rectangle.on.rectangle", accessibilityDescription: "Add Capture")
        add.imagePosition = .imageLeading
        add.bezelStyle = .rounded
        add.toolTip = "Capture an area and add it to this canvas (⇧⌘A)"

        for (index, (symbol, tip)) in [
            ("rectangle.split.1x2", "Stack the captures in a column"),
            ("rectangle.split.2x1", "Put the captures side by side"),
        ].enumerated() {
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip) {
                direction.setImage(image, forSegment: index)
                direction.setLabel("", forSegment: index)
                direction.setWidth(30, forSegment: index)
            }
            direction.setToolTip(tip, forSegment: index)
        }
        direction.target = self
        direction.action = #selector(changeLayout)
        aligner.target = self
        aligner.action = #selector(changeLayout)

        for choice in Self.gaps { gap.addItem(withTitle: choice.title) }
        gap.toolTip = "Gap between captures"
        gap.target = self
        gap.action = #selector(changeLayout)

        for view in [add, direction, aligner, gap] { addArrangedSubview(view) }
        update()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func update() {
        let document = model.document
        let combined = document.images.count > 1
        for view in [direction, aligner, gap] { view.isHidden = !combined }
        guard combined else { return }
        let layout = document.layout
        direction.selectedSegment = layout.direction == .vertical ? 0 : 1
        // The alignment icons follow the direction: left/center/right for a column,
        // top/middle/bottom for a row.
        let symbols = layout.direction == .vertical
            ? ["align.horizontal.left", "align.horizontal.center", "align.horizontal.right"]
            : ["align.vertical.top", "align.vertical.center", "align.vertical.bottom"]
        let tips = layout.direction == .vertical ? ["Left", "Center", "Right"] : ["Top", "Middle", "Bottom"]
        for index in 0..<3 {
            if let image = NSImage(systemSymbolName: symbols[index], accessibilityDescription: tips[index]) {
                aligner.setImage(image, forSegment: index)
                aligner.setLabel("", forSegment: index)
                aligner.setWidth(28, forSegment: index)
            }
            aligner.setToolTip("Align \(tips[index].lowercased())", forSegment: index)
        }
        aligner.selectedSegment = CombineLayout.Alignment.allCases.firstIndex(of: layout.alignment) ?? 0
        let points = Double(layout.spacing) / document.scale
        gap.selectItem(at: Self.gaps.firstIndex { abs($0.points - points) < 0.5 } ?? 2)
    }

    @objc private func changeLayout() {
        let layout = CombineLayout(
            direction: direction.selectedSegment == 1 ? .horizontal : .vertical,
            alignment: CombineLayout.Alignment.allCases[max(aligner.selectedSegment, 0)],
            spacing: Int((Self.gaps[max(gap.indexOfSelectedItem, 0)].points * model.document.scale).rounded())
        )
        guard layout != model.document.layout else { return }
        model.edit("Layout") { $0.setLayout(layout) }
    }
}
