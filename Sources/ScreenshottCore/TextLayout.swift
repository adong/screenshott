import CoreGraphics
import CoreText
import Foundation

/// How text annotations are set: the bold system font, one line per newline. The
/// editor's text field uses the same font, so typing and the result line up.
public enum TextLayout {
    public static func font(size: Double) -> CTFont {
        CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    }

    public static func lineHeight(fontSize: Double) -> Double {
        let font = font(size: fontSize)
        return ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
    }

    /// The box the text fills. Never narrower than half the font size, so an empty
    /// annotation still has something to click.
    public static func size(of text: String, fontSize: Double) -> CGSize {
        let lines = self.lines(text, fontSize: fontSize, color: nil)
        let width = lines.map { CTLineGetTypographicBounds($0, nil, nil, nil) }.max() ?? 0
        return CGSize(
            width: max(ceil(width), fontSize / 2),
            height: lineHeight(fontSize: fontSize) * Double(max(lines.count, 1))
        )
    }

    /// Draws `text` with its top-left corner at `origin`, in a context whose y axis
    /// points down (the canvas's).
    public static func draw(_ text: String, fontSize: Double, color: CGColor, at origin: CGPoint, in context: CGContext) {
        let font = font(size: fontSize)
        let height = lineHeight(fontSize: fontSize)
        context.saveGState()
        defer { context.restoreGState() }
        // CoreText draws y-up; flipping the text matrix keeps glyphs upright.
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for (index, line) in lines(text, fontSize: fontSize, color: color).enumerated() {
            context.textPosition = CGPoint(x: origin.x, y: origin.y + Double(index) * height + CTFontGetAscent(font))
            CTLineDraw(line, context)
        }
    }

    private static func lines(_ text: String, fontSize: Double, color: CGColor?) -> [CTLine] {
        var attributes: [NSAttributedString.Key: Any] = [.init(kCTFontAttributeName as String): font(size: fontSize)]
        if let color { attributes[.init(kCTForegroundColorAttributeName as String)] = color }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map {
            CTLineCreateWithAttributedString(NSAttributedString(string: String($0), attributes: attributes))
        }
    }
}
