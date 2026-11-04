import AppKit
import Carbon.HIToolbox
import ScreenshottCore

/// One ⌘⇧2 session: a frozen overlay panel on every display and one selection across
/// all of them. A selection stays on the display where its drag started (decision 4a).
@MainActor
final class OverlayController {
    struct Result {
        let image: CGImage
        let scale: CGFloat
        let screen: NSScreen
        let action: Delivery.Action
        /// What was captured, in Cocoa global points — remembered for Repeat Last Area.
        let area: CGRect
    }

    /// What Enter and a double-click run: the preset's action.
    let enterAction: Delivery.Action
    /// The action bar under the selection; its workflows also answer to 1–9.
    let barItems: [OverlayActionBar.Item]
    /// Off in Settings: no loupe, only the coordinates and color beside the pointer.
    /// Settable for the README shots, which show both.
    var showsMagnifier: Bool

    private var panels: [OverlayPanel] = []
    private var views: [OverlayView] = []
    private let onFinish: (Result?) -> Void
    private var finished = false
    /// Where the pointer is, in Cocoa global points. Tracked here rather than read from
    /// NSEvent.mouseLocation so arrow-key warps add up even before the system catches up.
    private var pointer = NSEvent.mouseLocation

    init(
        capture: FrozenCapture, windows: [CGRect], enterAction: Delivery.Action = .standard,
        barItems: [OverlayActionBar.Item] = [], showsMagnifier: Bool = true, onFinish: @escaping (Result?) -> Void
    ) {
        self.enterAction = enterAction
        self.barItems = barItems
        self.showsMagnifier = showsMagnifier
        self.onFinish = onFinish
        for display in capture.displays {
            let panel = OverlayPanel(
                contentRect: display.screen.frame,
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
            )
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.isOpaque = true
            panel.hasShadow = false
            panel.backgroundColor = .black
            panel.acceptsMouseMovedEvents = true
            panel.animationBehavior = .none

            let geometry = display.geometry
            let windowRects = windows.compactMap {
                geometry.pixelRect(forGlobal: $0, displayBounds: display.displayBounds)
            }
            let view = OverlayView(display: display, windows: windowRects, controller: self)
            panel.contentView = view
            panels.append(panel)
            views.append(view)
        }
    }

    func show() {
        for (panel, view) in zip(panels, views) {
            panel.setFrame(view.display.screen.frame, display: false)
            panel.orderFrontRegardless()
        }
        if let view = viewUnderPointer, let panel = view.window {
            panel.makeKey()
            _ = panel.makeFirstResponder(view)
        }
        // Draw the loupe and window highlight now rather than on the first mouse move.
        pointerMoved(toScreen: pointer)
    }

    // MARK: - Called by the views

    var selectionView: OverlayView? { views.first { $0.hasSelection } }

    /// Tells exactly one view it has the pointer — on a shared edge both screens would
    /// otherwise claim it and draw two loupes.
    func pointerMoved(toScreen p: CGPoint) {
        pointer = p
        let under = viewUnderPointer
        for view in views { view.pointerMoved(toScreen: view === under ? p : nil) }
    }

    /// A press on one display clears the selection on the others.
    func pressBegan(in view: OverlayView) {
        for other in views where other !== view { other.clearSelection() }
        if let panel = view.window, !panel.isKeyWindow {
            panel.makeKey()
            _ = panel.makeFirstResponder(view)
        }
    }

    @discardableResult
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        switch Int(event.keyCode) {
        case kVK_Escape:
            finish(nil)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            confirm(enterAction)
            return true
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow:
            arrow(Int(event.keyCode), flags: flags)
            return true
        default:
            break
        }
        let key = event.charactersIgnoringModifiers?.lowercased()
        if flags == .command, key == "c" {
            // Nothing selected yet: the color picker. A selection: the image.
            if selectionView == nil, let color = viewUnderPointer?.colorUnderPointer {
                copy(color)
            } else {
                confirm(.copyOnly)
            }
        } else if flags == .command, key == "s" {
            confirm(.saveAs)
        } else if flags.isEmpty, key == "e" {
            confirm(.editor)
        } else if flags.isEmpty, let key, let n = Int(key), (1...9).contains(n) {
            let workflows = barItems.filter { $0.action.workflowID != nil }
            if workflows.indices.contains(n - 1) { confirm(workflows[n - 1].action) } else { NSSound.beep() }
        } else if flags.isEmpty, key == "p" {
            Log.write("overlay: P (pin) arrives in P1")
            NSSound.beep()
        } else {
            return false
        }
        return true
    }

    /// Captures what Enter would: the selection, else the window under the pointer.
    func confirm(_ action: Delivery.Action) {
        guard let view = selectionView ?? viewUnderPointer,
              let rect = view.target, !rect.isEmpty,
              let image = view.display.image.cropping(to: rect.cgRect)
        else {
            NSSound.beep()
            return
        }
        let origin = view.display.screen.frame.origin
        let area = view.geometry.viewRect(for: rect).offsetBy(dx: origin.x, dy: origin.y)
        finish(Result(image: image, scale: view.geometry.scale, screen: view.display.screen, action: action, area: area))
    }

    /// The color picker's ⌘C: the pixel's hex on the clipboard, then the overlay closes
    /// like any other copy.
    private func copy(_ color: PixelColor) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(color.hex, forType: .string)
        Log.write("overlay: copied color \(color.hex)")
        finish(nil)
        Toast.show("Copied \(color.hex)")
    }

    /// For the README shots: a selection in the middle of the display under the pointer,
    /// with the pointer parked on its bottom-right corner as if mid-drag, so the size
    /// label, handles and loupe all show. Returns that display's screen.
    func stageForReadme() -> NSScreen? {
        guard let view = viewUnderPointer ?? views.first else { return nil }
        let size = view.geometry.pixelSize
        view.stage(selection: PixelRect(
            x: size.width * 3 / 10, y: size.height / 4, width: size.width * 2 / 5, height: size.height * 2 / 5
        ))
        guard let rect = view.target else { return nil }
        let corner = view.geometry.viewRect(for: rect)
        let origin = view.display.screen.frame.origin
        pointerMoved(toScreen: CGPoint(x: origin.x + corner.maxX, y: origin.y + corner.minY))
        return view.display.screen
    }

    // MARK: - Private

    private var viewUnderPointer: OverlayView? {
        DisplayPicking.index(containing: pointer, in: views.map(\.display.screen.frame)).map { views[$0] }
    }

    /// Arrows move the selection one pixel (⇧: ten); ⌥ moves its right and bottom edges
    /// instead. With no selection they move the pointer itself, for lining up a drag.
    private func arrow(_ keyCode: Int, flags: NSEvent.ModifierFlags) {
        let step = flags.contains(.shift) ? 10 : 1
        let (dx, dy) = switch keyCode {
        case kVK_LeftArrow: (-step, 0)
        case kVK_RightArrow: (step, 0)
        case kVK_UpArrow: (0, -step)  // pixel space counts down from the top
        default: (0, step)
        }
        if let view = selectionView {
            if flags.contains(.option) { view.resizeSelection(dx: dx, dy: dy) } else { view.nudgeSelection(dx: dx, dy: dy) }
        } else if let view = viewUnderPointer {
            warpPointer(dx: dx, dy: dy, within: view)
        }
    }

    private func warpPointer(dx: Int, dy: Int, within view: OverlayView) {
        let scale = view.geometry.scale
        let frame = view.display.screen.frame
        let pixel = 1 / scale
        let p = CGPoint(
            x: min(max(pointer.x + CGFloat(dx) / scale, frame.minX), frame.maxX - pixel),
            y: min(max(pointer.y - CGFloat(dy) / scale, frame.minY + pixel), frame.maxY)
        )
        let mainHeight = NSScreen.screens.first?.frame.height ?? frame.height
        CGWarpMouseCursorPosition(GlobalCoordinates.cgPoint(fromCocoa: p, mainScreenHeight: mainHeight))
        // A warp normally freezes the real mouse for a moment; this lifts that.
        CGAssociateMouseAndMouseCursorPosition(1)
        pointerMoved(toScreen: p)
    }

    private func finish(_ result: Result?) {
        guard !finished else { return }
        finished = true
        for panel in panels { panel.orderOut(nil) }
        NSCursor.arrow.set()
        onFinish(result)
    }
}

/// A borderless panel can't take the keyboard unless it says so.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Keep the full-screen frame; AppKit would otherwise push it below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
