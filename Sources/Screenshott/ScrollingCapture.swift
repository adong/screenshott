import AppKit
import Carbon.HIToolbox
import ScreenshottCore

/// One ⌥⌘⇧2 session. The screen stays live: drag over the part that scrolls, or click
/// to take the scroll area (or window) under the pointer. Then Enter auto-scrolls it, or
/// M lets you scroll it yourself, while frames are stitched as they come and a strip at
/// the screen edge shows the result growing. Enter saves, Esc cancels. Auto-scroll also
/// stops by itself at the bottom, and both stop at 30,000 px.
///
/// While capturing, the app being captured gets focus back — so it looks the way you see
/// it and takes your scrolling — and Return and Esc are held as global hotkeys, so they
/// end the capture instead of reaching that app.
@MainActor
final class ScrollingCapture: NSObject {
    enum Mode: String {
        case auto, manual
    }

    /// A region and a way to scroll it chosen in code rather than with the mouse — for
    /// the README demo, which scrolls a page of our own.
    struct Stage {
        let screen: NSScreen
        /// In that screen's pixels, top-left origin.
        let selection: PixelRect
        let scroller: ScrollDriver
        /// Our own windows to capture anyway: the page being scrolled.
        let including: Set<Int>
        /// Gets the stitched image before it is delivered.
        let onResult: (CGImage) -> Void
    }

    private enum Phase {
        case selecting, capturing, finishing
    }

    @MainActor
    private struct Region {
        let view: ScrollSelectionView
        let rect: PixelRect
        var screen: NSScreen { view.screen }
        var scale: CGFloat { view.geometry.scale }

        /// The region in Cocoa global points.
        var cocoaFrame: CGRect {
            view.geometry.viewRect(for: rect).offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        }
    }

    private let delivery: Delivery
    private let onFinish: () -> Void
    private var panels: [OverlayPanel] = []
    private var views: [ScrollSelectionView] = []
    private var pointer = NSEvent.mouseLocation
    private var previousApp: NSRunningApplication?
    private var stage: Stage?
    private var phase = Phase.selecting
    private var mode = Mode.manual
    private var region: Region?
    private var session: ScrollSession?
    private var preview: ScrollPreview?
    private var started = ContinuousClock.now
    /// Updates from the session, and what the stitcher did since the last scroll.
    private var updates = 0
    private var lastUpdate = ContinuousClock.now
    private var steps: [ScrollStitcher.Step] = []
    private var body = 0
    private var warned = false
    /// Return / keypad Enter / Esc as global hotkeys while capturing.
    private static let hotKeys: [(id: UInt32, keyCode: Int, label: String, save: Bool)] = [
        (100, kVK_Return, "↩", true), (101, kVK_ANSI_KeypadEnter, "⌤", true), (102, kVK_Escape, "⎋", false),
    ]

    private static let modeTitles: [Mode: String] = [.auto: "Auto-scrolling", .manual: "Scroll the area"]
    private static let keysHint = "↩ save · Esc cancel"

    init(delivery: Delivery, onFinish: @escaping () -> Void) {
        self.delivery = delivery
        self.onFinish = onFinish
    }

    /// Puts the live overlay on every display. With a `stage`, skips the selection and
    /// starts auto-scrolling it at once.
    func begin(stage: Stage? = nil) {
        self.stage = stage
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApp = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost
        // Before anything of ours is on screen.
        let windows = ScrollTargets.windows()
        for screen in NSScreen.screens {
            let panel = OverlayPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.acceptsMouseMovedEvents = true
            panel.animationBehavior = .none
            let view = ScrollSelectionView(screen: screen, windows: windows, controller: self)
            view.connectButtons(to: self)
            panel.contentView = view
            panels.append(panel)
            views.append(view)
        }
        for (panel, view) in zip(panels, views) {
            panel.setFrame(view.screen.frame, display: false)
            panel.orderFrontRegardless()
        }
        if let stage, let view = views.first(where: { $0.screen == stage.screen }) {
            view.stage(selection: stage.selection)
            startCapture(.auto)
            return
        }
        if let view = viewUnderPointer, let panel = view.window {
            panel.makeKey()
            _ = panel.makeFirstResponder(view)
        }
        // Taking focus is what lets the overlay set the crosshair cursor.
        NSApp.activate()
        pointerMoved(toScreen: pointer)
        Log.write("scrolling overlay shown, \(windows.count) windows, accessibility=\(Accessibility.isTrusted)")
    }

    // MARK: - Called by the views

    var selectionView: ScrollSelectionView? { views.first { $0.hasSelection } }

    func pointerMoved(toScreen p: CGPoint) {
        pointer = p
        let under = viewUnderPointer
        for view in views { view.pointerMoved(toScreen: view === under ? p : nil) }
    }

    func pressBegan(in view: ScrollSelectionView) {
        for other in views where other !== view { other.clearSelection() }
        if let panel = view.window, !panel.isKeyWindow {
            panel.makeKey()
            _ = panel.makeFirstResponder(view)
        }
    }

    @objc func autoClicked() { startCapture(.auto) }

    @objc func manualClicked() { startCapture(.manual) }

    @discardableResult
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        switch Int(event.keyCode) {
        case kVK_Escape:
            finish(save: false, reason: "esc")
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if phase == .selecting { startCapture(.auto) } else { finish(save: true, reason: "enter") }
            return true
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow:
            guard phase == .selecting, let view = selectionView else { return true }
            let step = flags.contains(.shift) ? 10 : 1
            let (dx, dy) = switch Int(event.keyCode) {
            case kVK_LeftArrow: (-step, 0)
            case kVK_RightArrow: (step, 0)
            case kVK_UpArrow: (0, -step)
            default: (0, step)
            }
            if flags.contains(.option) { view.resizeSelection(dx: dx, dy: dy) } else { view.nudgeSelection(dx: dx, dy: dy) }
            return true
        default:
            break
        }
        if phase == .selecting, flags.isEmpty, event.charactersIgnoringModifiers?.lowercased() == "m" {
            startCapture(.manual)
            return true
        }
        return false
    }

    /// Starts streaming the selection; auto mode also starts scrolling it.
    func startCapture(_ requested: Mode) {
        guard phase == .selecting, let view = selectionView, let rect = view.selection,
              rect.width >= 16, rect.height >= 48, let displayID = view.screen.displayID
        else {
            NSSound.beep()
            return
        }
        var note = ""
        mode = requested
        if mode == .auto, stage == nil, !Accessibility.isTrusted {
            // The system prompt (first time only) shows through the overlay, which lets
            // clicks through from here on.
            Accessibility.requestIfNeeded()
            mode = .manual
            note = "Auto-scroll needs Accessibility: Privacy & Security → Accessibility. Scroll it yourself this time."
            Log.write("scrolling: no Accessibility permission, manual instead")
        }
        phase = .capturing
        started = .now
        let region = Region(view: view, rect: rect)
        self.region = region

        for (panel, view) in zip(panels, views) {
            panel.ignoresMouseEvents = true
            view.enterCapture()
        }
        NSCursor.arrow.set()
        let preview = ScrollPreview(on: region.screen, avoiding: region.cocoaFrame, regionPixelWidth: rect.width)
        preview.setStatus(Self.modeTitles[mode]!, detail: note.isEmpty ? Self.keysHint : note, warning: !note.isEmpty)
        preview.show()
        self.preview = preview
        warned = !note.isEmpty

        if stage == nil { _ = previousApp?.activate(options: []) }
        bindHotKeys()

        let scale = region.scale
        let session = ScrollSession(
            displayID: displayID,
            // Overlay scrollers sit in the last 16 points and move as the page does.
            ignoredColumns: Int((16 * scale).rounded()),
            previewFactor: CGFloat(rect.width) / ((ScrollPreview.width - 12) * scale),
            onUpdate: { [weak self] in self?.handle($0) },
            onStop: { [weak self] error in
                Log.write("scrolling stream stopped: \(error)")
                self?.finish(save: true, reason: "stream stopped")
            }
        )
        self.session = session
        let sourceRect = CGRect(
            x: CGFloat(rect.x) / scale, y: CGFloat(rect.y) / scale,
            width: CGFloat(rect.width) / scale, height: CGFloat(rect.height) / scale
        )
        let center = region.cocoaFrame
        let mainHeight = NSScreen.screens.first?.frame.height ?? center.maxY
        let scroller = stage?.scroller ?? WheelScroller(
            location: GlobalCoordinates.cgPoint(fromCocoa: CGPoint(x: center.midX, y: center.midY), mainScreenHeight: mainHeight)
        )
        Task {
            do {
                try await session.start(sourceRect: sourceRect, pixelSize: rect.size, including: stage?.including ?? [])
            } catch {
                Log.write("scrolling stream failed to start: \(error)")
                NSSound.beep()
                finish(save: false, reason: "stream failed")
                return
            }
            Log.write(String(
                format: "scrolling %@ %dx%d @%.0fx started in %.1fms", mode.rawValue, rect.width, rect.height, scale,
                (ContinuousClock.now - started).milliseconds
            ))
            if mode == .auto { await runAuto(scroller, regionHeight: rect.height, scale: scale) }
        }
    }

    // MARK: - Capturing

    private func handle(_ update: ScrollSession.Update) {
        guard phase == .capturing else { return }
        updates += 1
        lastUpdate = .now
        steps.append(update.step)
        body = update.body
        if let frames = update.preview { preview?.update(frames, height: update.height) }
        switch update.step {
        case .full:
            finish(save: true, reason: "full")
        case .lost:
            preview?.flash()
            if mode == .manual {
                warned = true
                preview?.setStatus(Self.modeTitles[mode]!, detail: "Lost the overlap. Scroll back up a little.", warning: true)
            }
        case .appended where warned:
            warned = false
            preview?.setStatus(Self.modeTitles[mode]!, detail: Self.keysHint)
        default:
            break
        }
    }

    /// One scroll at a time: post it, let the frames settle, ask the plan what next.
    private func runAuto(_ scroller: ScrollDriver, regionHeight: Int, scale: CGFloat) async {
        await settle(after: 0, timeout: .seconds(2))
        var plan = AutoScrollPlan(regionHeight: regionHeight, scale: Double(scale))
        var action = plan.start()
        var scrolls = 0
        while phase == .capturing, case .scroll(let points) = action {
            steps = []
            session?.expect(shift: plan.expectedShift(for: points))
            let mark = updates
            await scroller.scroll(points: points, inverted: plan.inverted)
            scrolls += 1
            await settle(after: mark, timeout: .milliseconds(700))
            guard phase == .capturing else { return }
            action = plan.next(after: .summarizing(steps, body: body))
        }
        if phase == .capturing, case .stop(let reason) = action {
            Log.write("scrolling auto stopped: \(reason.rawValue) after \(scrolls) scrolls\(plan.inverted ? " (wheel inverted)" : "")")
            finish(save: true, reason: reason.rawValue)
        }
    }

    /// Returns once frames have come in after update `mark` and then stopped for a
    /// moment, or after `timeout` when none come — the scroll moved nothing.
    private func settle(after mark: Int, timeout: Duration) async {
        let start = ContinuousClock.now
        while phase == .capturing {
            try? await Task.sleep(for: .milliseconds(15))
            let now = ContinuousClock.now
            if updates > mark, now - lastUpdate >= .milliseconds(150) { return }
            if now - start >= timeout { return }
        }
    }

    // MARK: - Ending

    private func finish(save: Bool, reason: String) {
        switch phase {
        case .finishing:
            return
        case .selecting:
            phase = .finishing
            closeOverlay()
            Log.write("capture scrolling cancelled")
            _ = previousApp?.activate(options: [])
            onFinish()
        case .capturing:
            phase = .finishing
            unbindHotKeys()
            let elapsed = ContinuousClock.now - started
            let mode = mode
            Task {
                await session?.stop()
                let result = save ? await session?.result() : nil
                closeOverlay()
                if let result, let image = result.image, let region {
                    stage?.onResult(image)
                    delivery.deliver(
                        image, scale: region.scale, on: region.screen, action: .standard,
                        log: String(
                            format: "capture scrolling %dx%d @%.0fx %@ stop=%@ frames=%d kept=%d header=%d footer=%d%@ in %.1fs",
                            image.width, image.height, region.scale, mode.rawValue, reason, result.frames,
                            result.accepted, result.header, result.footer, result.scrollerCut ? " scroller-cut" : "",
                            elapsed.milliseconds / 1000
                        )
                    )
                } else {
                    Log.write("capture scrolling cancelled (\(reason))")
                }
                onFinish()
            }
        }
    }

    private func closeOverlay() {
        for panel in panels { panel.orderOut(nil) }
        preview?.close()
        NSCursor.arrow.set()
    }

    private func bindHotKeys() {
        var held = true
        for key in Self.hotKeys {
            let status = HotKeys.bind(key.id, to: Shortcut(keyCode: UInt32(key.keyCode), modifiers: 0, key: key.label)) {
                [weak self] in self?.finish(save: key.save, reason: key.save ? "enter" : "esc")
            }
            if status != noErr {
                held = false
                Log.write("scrolling: can't hold \(key.label) as a hotkey (\(status))")
            }
        }
        // Without them, keep the keyboard ourselves: the overlay still takes keys while
        // it lets the mouse through.
        if !held, let panel = region?.view.window {
            NSApp.activate()
            panel.makeKey()
            _ = panel.makeFirstResponder(region?.view)
        }
    }

    private func unbindHotKeys() {
        for key in Self.hotKeys { HotKeys.bind(key.id, to: nil) {} }
    }

    private var viewUnderPointer: ScrollSelectionView? {
        DisplayPicking.index(containing: pointer, in: views.map(\.screen.frame)).map { views[$0] }
    }
}
