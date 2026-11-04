import AppKit
import ScreenshottCore

/// The editor's part of `--readme-shots`: a made-up checkout card over the stock
/// wallpaper, captured for real, then marked up in the editor by code — a mosaic over
/// the card number, a solid cover over the email, a box, a note and an arrow. Nothing
/// on it came from the real screen.
extension AppDelegate {
    func runEditorReadmeShots(on screen: NSScreen, into directory: URL) async {
        let card = ReadmeCard()
        // Room around the card for the note and the arrow.
        let margin = (left: 60.0, top: 50.0, right: 250.0, bottom: 60.0)
        let size = card.frame.size
        let region = CGRect(
            x: screen.frame.midX - (size.width + margin.left + margin.right) / 2,
            y: screen.frame.midY - (size.height + margin.top + margin.bottom) / 2,
            width: size.width + margin.left + margin.right, height: size.height + margin.top + margin.bottom
        )
        let window = NSWindow(
            contentRect: CGRect(x: region.minX + margin.left, y: region.minY + margin.bottom, width: size.width, height: size.height),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.contentView = card
        window.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(500))

        let capture: CGImage, scale: CGFloat
        do {
            let frozen = try await ScreenCapturer.capture([screen], excluding: [])
            guard let display = frozen.displays.first else { throw CaptureError.noDisplay }
            let frame = screen.frame
            let crop = CGRect(
                x: (region.minX - frame.minX) * display.scale, y: (frame.maxY - region.maxY) * display.scale,
                width: region.width * display.scale, height: region.height * display.scale
            ).integral
            guard let image = display.image.cropping(to: crop) else { throw CaptureError.encodeFailed }
            (capture, scale) = (image, display.scale)
        } catch {
            Log.write("readme-shots editor capture failed: \(error)")
            window.orderOut(nil)
            return
        }
        window.orderOut(nil)

        let editor = delivery.editors.open(capture, scale: scale)
        let model = editor.model
        // Card points (y down from the card's top-left) → canvas pixels.
        func canvas(_ r: CGRect) -> CGRect {
            CGRect(x: (r.minX + margin.left) * scale, y: (r.minY + margin.top) * scale, width: r.width * scale, height: r.height * scale)
        }
        func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: (x + margin.left) * scale, y: (y + margin.top) * scale) }
        let red = RGBAColor.palette[0]
        let email = canvas(card.valueRect(row: 1).insetBy(dx: -6, dy: -4))
        let number = canvas(card.valueRect(row: 2).insetBy(dx: -6, dy: -4))
        let total = canvas(card.rowRect(row: 3))
        let button = card.buttonRect
        // Sizes first: the edit below has the document checked out.
        let lineWidth = model.size(for: .rectangle), fontSize = model.size(for: .text)
        let arrow = Annotation(
            kind: .arrow, start: point(size.width + 120, size.height + 40), end: point(button.maxX - 24, button.midY + 4),
            color: red, size: lineWidth
        )
        model.edit("README") { document in
            document.add(Annotation(kind: .pixelate, start: number.origin, end: CGPoint(x: number.maxX, y: number.maxY), size: 0))
            document.add(Annotation(
                kind: .pixelate, start: email.origin, end: CGPoint(x: email.maxX, y: email.maxY), color: .black,
                size: 0, cover: .solid
            ))
            document.add(Annotation(
                kind: .rectangle, start: total.origin, end: CGPoint(x: total.maxX, y: total.maxY), color: red,
                size: lineWidth
            ))
            // A warning triangle (equilateral, as ⇧ draws it) ahead of the note.
            let warning = point(size.width + 24, card.rowRect(row: 3).minY + 4)
            let side = 18 * scale
            document.add(Annotation(
                kind: .triangle, start: warning, end: CGPoint(x: warning.x + side, y: warning.y + side * 3.squareRoot() / 2),
                color: red, size: lineWidth
            ))
            let note = point(size.width + 24 + 26, card.rowRect(row: 3).minY + 2)
            document.add(Annotation(
                kind: .text, start: note, end: note, color: red, size: fontSize, text: "Is this right?"
            ))
            let pay = canvas(button.insetBy(dx: -14, dy: -10))
            document.add(Annotation(
                kind: .ellipse, start: pay.origin, end: CGPoint(x: pay.maxX, y: pay.maxY), color: red, size: lineWidth
            ))
            document.add(arrow)
        }
        model.selection = arrow.id

        guard let editorWindow = editor.window else { return }
        editorWindow.level = .floating
        editorWindow.setFrameOrigin(CGPoint(
            x: screen.frame.midX - editorWindow.frame.width / 2, y: screen.frame.midY - editorWindow.frame.height / 2
        ))
        editorWindow.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(900))
        await ReadmeShots.photograph(editorWindow.frame.insetBy(dx: -40, dy: -40), of: screen, as: "editor.png", in: directory)

        // 5. Combine, through the real Add Capture path: the editor steps aside, the
        // overlay opens, and its staged selection — over a second made-up card in the
        // middle of the screen — lands on the canvas below the first capture.
        model.selection = nil
        let confirmation = ReadmeCard.confirmation
        let staged = CGPoint(x: screen.frame.midX, y: screen.frame.maxY - screen.frame.height * 0.45)
        window.contentView = confirmation
        window.setFrame(CGRect(
            x: staged.x - confirmation.frame.width / 2, y: staged.y - confirmation.frame.height / 2,
            width: confirmation.frame.width, height: confirmation.frame.height
        ), display: true)
        window.orderFrontRegardless()
        editor.addCapture(nil)
        for _ in 0..<60 where overlay == nil { try? await Task.sleep(for: .milliseconds(50)) }
        guard let overlay, overlay.stageForReadme() != nil else {
            Log.write("readme-shots: Add Capture's overlay did not open")
            window.orderOut(nil)
            model.markSaved()
            editorWindow.close()
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        overlay.confirm(.standard)
        window.orderOut(nil)
        let gap = Int((16 * scale).rounded())
        model.edit("README") { $0.setLayout(CombineLayout(direction: .vertical, alignment: .center, spacing: gap)) }
        try? await Task.sleep(for: .milliseconds(900))
        await ReadmeShots.photograph(editorWindow.frame.insetBy(dx: -40, dy: -40), of: screen, as: "combine.png", in: directory)
        model.markSaved()
        editorWindow.close()
    }
}

/// Forms that never existed: something worth pointing at and redacting.
@MainActor
private final class ReadmeCard: NSView {
    private let title: String
    private let rows: [(String, String)]
    private let button: (title: String, color: NSColor)
    private static let valueFont = NSFont.systemFont(ofSize: 15, weight: .medium)

    init(
        title: String = "Checkout",
        rows: [(String, String)] = [
            ("Name", "Jane Appleseed"),
            ("Email", "jane.appleseed@example.com"),
            ("Card", "4242 4242 4242 4242"),
            ("Total", "$48.00"),
        ],
        button: (title: String, color: NSColor) = ("Pay now", NSColor(red: 0.04, green: 0.45, blue: 0.95, alpha: 1))
    ) {
        self.title = title
        self.rows = rows
        self.button = button
        super.init(frame: CGRect(x: 0, y: 0, width: 420, height: 310))
    }

    static var confirmation: ReadmeCard {
        ReadmeCard(
            title: "Order confirmed",
            rows: [("Order", "#48213"), ("Arrives", "Thursday, Nov 6"), ("Paid", "$48.00"), ("Ship to", "Cupertino, CA")],
            button: ("Track package", NSColor(red: 0.13, green: 0.65, blue: 0.32, alpha: 1))
        )
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    private func rowY(_ row: Int) -> Double { 80 + Double(row) * 42 }

    func valueRect(row: Int) -> CGRect {
        let size = (rows[row].1 as NSString).size(withAttributes: [.font: Self.valueFont])
        return CGRect(x: 120, y: rowY(row), width: ceil(size.width), height: ceil(size.height))
    }

    func rowRect(row: Int) -> CGRect { CGRect(x: 16, y: rowY(row) - 9, width: bounds.width - 32, height: 38) }

    var buttonRect: CGRect { CGRect(x: 28, y: 252, width: bounds.width - 56, height: 38) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()
        (title as NSString).draw(at: CGPoint(x: 28, y: 26), withAttributes: [
            .font: NSFont.systemFont(ofSize: 24, weight: .bold), .foregroundColor: NSColor(white: 0.1, alpha: 1),
        ])
        for (row, (label, value)) in rows.enumerated() {
            (label as NSString).draw(at: CGPoint(x: 28, y: rowY(row)), withAttributes: [
                .font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor(white: 0.45, alpha: 1),
            ])
            (value as NSString).draw(at: CGPoint(x: 120, y: rowY(row)), withAttributes: [
                .font: Self.valueFont, .foregroundColor: NSColor(white: 0.1, alpha: 1),
            ])
        }
        button.color.setFill()
        NSBezierPath(roundedRect: buttonRect, xRadius: 9, yRadius: 9).fill()
        let title = button.title as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16, weight: .semibold), .foregroundColor: NSColor.white]
        let titleSize = title.size(withAttributes: attributes)
        title.draw(at: CGPoint(x: buttonRect.midX - titleSize.width / 2, y: buttonRect.midY - titleSize.height / 2), withAttributes: attributes)
    }
}
