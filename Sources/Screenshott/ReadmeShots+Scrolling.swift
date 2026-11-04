import AppKit
import ScreenshottCore

/// The scrolling-capture shots: a tall page our own code draws — a sticky title bar, a
/// long document and a message box pinned at the bottom — auto-scrolled by the real
/// ⌥⌘⇧2 machinery and stitched. Nothing in them comes from the user's screen. The page
/// is scrolled directly rather than with wheel events, so this needs no Accessibility.
extension ReadmeShots {
    /// `--readme-only scrolling` runs just these shots.
    static var only: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "--readme-only"), arguments.indices.contains(flag + 1) else { return nil }
        return arguments[flag + 1]
    }
}

extension AppDelegate {
    func runScrollingReadmeShots(into directory: URL, on screen: NSScreen) async {
        // Its own wallpaper, above other apps' floating panels (a palette at the screen
        // edge showed through the shared one), and the page above that; all of it stays
        // under the overlay and the strip, which sit at screen-saver level.
        let cover = ReadmeShots.backdrop(on: screen)
        cover.level = .popUpMenu
        defer { cover.orderOut(nil) }
        let page = DemoPage(on: screen)
        page.window.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        page.window.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(600))

        let scale = screen.backingScaleFactor
        let frame = page.captureFrame
        let selection = PixelRect(
            x: Int(((frame.minX - screen.frame.minX) * scale).rounded()),
            y: Int(((screen.frame.maxY - frame.maxY) * scale).rounded()),
            width: Int((frame.width * scale).rounded()), height: Int((frame.height * scale).rounded())
        )
        var result: CGImage?
        startScrollingCapture(stage: ScrollingCapture.Stage(
            screen: screen, selection: selection, scroller: page, including: [page.window.windowNumber],
            onResult: { result = $0 }
        ))
        guard scrolling != nil else {
            Log.write("readme-shots: scrolling capture did not start")
            page.window.orderOut(nil)
            return
        }

        // Mid-scroll, once the stitch is about twice the page: the red frame on the page
        // and the strip growing at the edge.
        for _ in 0..<50 where (scrolling?.stitchedHeight ?? .max) < selection.height * 2 {
            try? await Task.sleep(for: .milliseconds(100))
        }
        let strip = NSApp.windows.first { $0.level.rawValue == NSWindow.Level.screenSaver.rawValue + 1 && $0.isVisible }
        var crop = (strip?.frame ?? frame).union(frame).insetBy(dx: -40, dy: -40).intersection(screen.visibleFrame)
        // Stop just outside the strip: past it is only the screen edge, where other apps
        // keep their edge handles.
        if let strip = strip?.frame {
            if strip.midX < frame.midX {
                crop = CGRect(x: strip.minX - 4, y: crop.minY, width: crop.maxX - strip.minX + 4, height: crop.height)
            } else {
                crop.size.width = strip.maxX + 4 - crop.minX
            }
        }
        await ReadmeShots.photograph(crop, of: screen, as: "scrolling.png", in: directory)

        for _ in 0..<200 where scrolling != nil { try? await Task.sleep(for: .milliseconds(100)) }
        page.window.orderOut(nil)
        guard let result, let png = PNGEncoder.data(from: result, scale: scale) else {
            Log.write("readme-shots: no stitched image")
            return
        }
        do {
            try png.write(to: directory.appendingPathComponent("scrolling-result.png"))
            Log.write("readme-shots wrote scrolling-result.png \(result.width)x\(result.height)")
        } catch {
            Log.write("readme-shots scrolling-result.png failed: \(error)")
        }
        // Let the thumbnail of the result land before the backdrop goes.
        try? await Task.sleep(for: .milliseconds(800))
    }
}

/// A window with a sticky title bar, a long scrolling document and a message box —
/// the shape of a chat or docs app, so the stitch has a header and a footer to drop.
@MainActor
private final class DemoPage: ScrollDriver {
    let window: NSWindow
    private let scrollView: NSScrollView
    private static let size = CGSize(width: 520, height: 600)
    private static let headerHeight: CGFloat = 56
    private static let footerHeight: CGFloat = 64

    /// The header, document and message box together, in Cocoa global points.
    var captureFrame: CGRect {
        window.convertToScreen(window.contentView?.frame ?? .zero)
    }

    init(on screen: NSScreen) {
        let origin = CGPoint(x: screen.frame.midX - Self.size.width / 2 + 120, y: screen.frame.midY - Self.size.height / 2)
        window = NSWindow(
            contentRect: CGRect(origin: origin, size: Self.size), styleMask: [.titled], backing: .buffered, defer: false
        )
        window.title = "Screenshott Notes"
        window.level = .floating
        window.isReleasedWhenClosed = false
        let content = NSView(frame: CGRect(origin: .zero, size: Self.size))
        window.contentView = content

        let header = Self.bar(
            CGRect(x: 0, y: Self.size.height - Self.headerHeight, width: Self.size.width, height: Self.headerHeight),
            color: NSColor(red: 0.29, green: 0.24, blue: 0.75, alpha: 1)
        )
        let title = NSTextField(labelWithString: "# release-notes")
        title.font = .systemFont(ofSize: 17, weight: .bold)
        title.textColor = .white
        title.frame = CGRect(x: 18, y: 18, width: 300, height: 22)
        header.addSubview(title)
        let members = NSTextField(labelWithString: "Screenshott · 7 milestones")
        members.font = .systemFont(ofSize: 12)
        members.textColor = NSColor.white.withAlphaComponent(0.75)
        members.alignment = .right
        members.frame = CGRect(x: Self.size.width - 218, y: 20, width: 200, height: 16)
        header.addSubview(members)

        let footer = Self.bar(
            CGRect(x: 0, y: 0, width: Self.size.width, height: Self.footerHeight), color: NSColor(white: 0.96, alpha: 1)
        )
        let field = Self.bar(CGRect(x: 14, y: 12, width: Self.size.width - 28, height: 40), color: .white)
        field.layer?.cornerRadius = 8
        field.layer?.borderWidth = 1
        field.layer?.borderColor = NSColor(white: 0.8, alpha: 1).cgColor
        let placeholder = NSTextField(labelWithString: "Message #release-notes")
        placeholder.font = .systemFont(ofSize: 14)
        placeholder.textColor = NSColor(white: 0.55, alpha: 1)
        placeholder.frame = CGRect(x: 12, y: 11, width: 300, height: 18)
        field.addSubview(placeholder)
        footer.addSubview(field)

        scrollView = NSScrollView(frame: CGRect(
            x: 0, y: Self.footerHeight, width: Self.size.width,
            height: Self.size.height - Self.headerHeight - Self.footerHeight
        ))
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .white
        let text = NSTextView(frame: CGRect(origin: .zero, size: scrollView.contentSize))
        text.isEditable = false
        text.isSelectable = false
        text.drawsBackground = true
        text.backgroundColor = .white
        text.textContainerInset = CGSize(width: 18, height: 16)
        text.isVerticallyResizable = true
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textStorage?.setAttributedString(Self.document())
        text.layoutManager?.ensureLayout(for: text.textContainer!)
        text.sizeToFit()
        scrollView.documentView = text

        for view in [scrollView, header, footer] { content.addSubview(view) }
        window.setFrameOrigin(origin)
    }

    func scroll(points: Double, inverted: Bool) async {
        let clip = scrollView.contentView
        let limit = max((scrollView.documentView?.frame.height ?? 0) - clip.bounds.height, 0)
        var origin = clip.bounds.origin
        origin.y = min(max(origin.y + CGFloat(inverted ? -points : points), 0), limit)
        clip.scroll(to: origin)
        scrollView.reflectScrolledClipView(clip)
    }

    private static func bar(_ frame: CGRect, color: NSColor) -> NSView {
        let view = NSView(frame: frame)
        view.wantsLayer = true
        view.layer?.backgroundColor = color.cgColor
        return view
    }

    /// Chat-style posts about each milestone: a name, a time, a few lines, and now and
    /// then a code line — varied enough that no two rows look alike.
    private static func document() -> NSAttributedString {
        let posts: [(String, String, [String])] = [
            ("Alan", "09:12", ["M0 is in: ⌘⇧1 grabs the display under the mouse and puts a PNG on the clipboard and in ~/Pictures/Screenshott.",
                               "Signed with a self-signed certificate, so the Screen Recording grant survives rebuilds."]),
            ("Travis", "09:40", ["Timing on the external display: 115 ms from hotkey to clipboard."]),
            ("Alan", "10:05", ["M1: ⌘⇧2 freezes every display. Drag, resize, move, arrow keys for 1 px.",
                               "Click without dragging and it snaps to the window under the pointer."]),
            ("Travis", "10:31", ["The loupe shows 15 × 15 pixels around the pointer with its coordinates.",
                                 "`overlay 1 display(s) 14 windows shown in 138.2ms`"]),
            ("Alan", "11:02", ["Thumbnails stack in the corner, five per screen, and never end up in the next capture."]),
            ("Travis", "11:20", ["Settings: record any shortcut, choose the folder, keep Retina resolution or save at 1x."]),
            ("Alan", "13:45", ["M2 next: every hotkey becomes a preset — frozen or live, area or window, and what Enter does."]),
            ("Travis", "14:10", ["M3 editor: arrow, rectangle, text and pixelate, with a solid-cover mode that really replaces the pixels.",
                                 "Projects keep the original next to the objects, so a capture can be edited again."]),
            ("Alan", "14:42", ["M4 Combine puts several captures on one canvas with automatic layout."]),
            ("Travis", "15:05", ["M5 scrolling capture: drag over a live window, then auto-scroll or scroll it yourself.",
                                 "Each frame is matched against the last by row hashes, and only the new rows are added.",
                                 "`shift=412 header=112 footer=128`"]),
            ("Alan", "15:30", ["Sticky headers come from the first frame only, and the message box from the last."]),
            ("Travis", "15:52", ["It stops when two scrolls in a row move nothing, at Enter, or at 30,000 px."]),
            ("Alan", "16:20", ["The strip at the screen edge shows the stitch while it grows. A bad seam shows up right away."]),
            ("Travis", "16:48", ["M6 polish: a bench mode with p50 and p95, measured against Shottr's 17 ms grab."]),
            ("Alan", "17:15", ["M7 workflows: scripts, Shortcuts or URL templates that get the image after a capture.",
                               "Scripts don't inherit our Screen Recording or Accessibility permission."]),
            ("Travis", "17:40", ["That's the v1 list. Built with nothing but the Command Line Tools."]),
        ]
        let out = NSMutableAttributedString()
        let body = NSMutableParagraphStyle()
        body.lineSpacing = 3
        body.paragraphSpacing = 6
        for (index, (name, time, lines)) in posts.enumerated() {
            let color = name == "Alan" ? NSColor(red: 0.85, green: 0.35, blue: 0.2, alpha: 1) : NSColor(red: 0.13, green: 0.5, blue: 0.4, alpha: 1)
            out.append(NSAttributedString(string: "\(name)  ", attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .bold), .foregroundColor: color,
            ]))
            out.append(NSAttributedString(string: "\(time)\n", attributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
            ]))
            for line in lines {
                let code = line.hasPrefix("`")
                out.append(NSAttributedString(string: (code ? line.trimmingCharacters(in: ["`"]) : line) + "\n", attributes: [
                    .font: code ? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) : NSFont.systemFont(ofSize: 14),
                    .foregroundColor: NSColor(white: 0.12, alpha: 1),
                    .backgroundColor: code ? NSColor(white: 0.94, alpha: 1) : NSColor.clear,
                    .paragraphStyle: body,
                ]))
            }
            if index < posts.count - 1 {
                out.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 6)]))
            }
        }
        return out
    }
}
