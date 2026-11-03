import AppKit
import ScreenshottCore

/// What Settings chooses per preset beyond its shortcut — what Enter runs and how long
/// a delayed preset counts down — plus the last area, for Repeat Last Area. Kept in
/// UserDefaults under `preset.<id>.*`.
@MainActor
final class PresetSettings: ObservableObject {
    @Published private var storedActions: [PresetID: String] = [:]
    @Published private var storedDelays: [PresetID: Int] = [:]
    private let defaults: UserDefaults

    private static let lastAreaKey = "lastArea"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        for id in PresetID.allCases {
            storedActions[id] = defaults.string(forKey: Self.key(id, "action"))
            storedDelays[id] = defaults.object(forKey: Self.key(id, "delay")) as? Int
        }
    }

    func action(for id: PresetID) -> CaptureAction {
        id.preset.action(stored: storedActions[id])
    }

    func setAction(_ action: CaptureAction, for id: PresetID) {
        storedActions[id] = action.name
        defaults.set(action.name, forKey: Self.key(id, "action"))
        Log.write("preset \(id.rawValue) enter = \(action.name)")
    }

    /// Countdown seconds; 0 for presets that don't count down.
    func delay(for id: PresetID) -> Int {
        id.preset.delay(stored: storedDelays[id])
    }

    func setDelay(_ seconds: Int, for id: PresetID) {
        storedDelays[id] = seconds
        defaults.set(seconds, forKey: Self.key(id, "delay"))
    }

    /// The last area captured, in Cocoa global points.
    var lastArea: CGRect? {
        get {
            guard let v = defaults.array(forKey: Self.lastAreaKey) as? [Double], v.count == 4 else { return nil }
            return CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
        }
        set {
            let v = newValue.map { [$0.minX, $0.minY, $0.width, $0.height].map(Double.init) }
            defaults.set(v, forKey: Self.lastAreaKey)
        }
    }

    private static func key(_ id: PresetID, _ name: String) -> String { "preset.\(id.rawValue).\(name)" }
}

/// Turns a preset into a capture: picks the screen and region it describes, then hands
/// the image to its Enter action through Delivery. Frozen area and full-screen captures
/// stay in AppDelegate; this adds the countdown, Repeat Last Area and Live Area.
@MainActor
final class PresetRunner {
    let settings = PresetSettings()
    private weak var app: AppDelegate?
    private let delivery: Delivery
    private var countdown: Task<Void, Never>?
    private lazy var countdownHUD = HUDPanel(size: CGSize(width: 150, height: 150), titleSize: 72)
    private var livePicker: LiveAreaPicker?

    init(app: AppDelegate, delivery: Delivery) {
        self.app = app
        self.delivery = delivery
    }

    func run(_ id: PresetID) {
        let preset = id.preset
        let action = settings.action(for: id)
        switch (preset.screen, preset.selection) {
        case (_, .none):
            Task { await app?.runFullScreenCapture(preset: id, then: action) }
        case (.frozen, .area):
            let delay = settings.delay(for: id)
            if delay > 0 {
                toggleCountdown(delay, preset: id, action: action)
            } else {
                let pressed = ContinuousClock.now
                Task { await app?.runAreaCapture(pressedAt: pressed, preset: id, enterAction: action) }
            }
        case (.live, .area):
            toggleLivePicker(preset: id, action: action)
        case (_, .lastArea):
            Task { await repeatLastArea(preset: id, action: action) }
        case (_, .scrolling):
            app?.runScrollingCapture()
        }
    }

    /// Every area capture is remembered, whichever preset took it.
    func remember(area: CGRect) {
        settings.lastArea = area
    }

    // MARK: - Delayed

    /// Counts down on the screen under the mouse, then opens the frozen overlay. Clicking
    /// the countdown or pressing the hotkey again cancels it.
    private func toggleCountdown(_ seconds: Int, preset id: PresetID, action: CaptureAction) {
        if countdown != nil {
            cancelCountdown()
            return
        }
        guard Permissions.hasScreenCapture else { return Permissions.showMissingScreenCaptureAlert() }
        guard let screen = ScreenCapturer.screenUnderMouse ?? NSScreen.main else { return }
        Log.write("preset \(id.rawValue): countdown \(seconds)s")
        countdownHUD.onClick = { [weak self] in self?.cancelCountdown() }
        countdownHUD.show("\(seconds)", detail: "Click to cancel", on: screen)
        countdown = Task { [weak self] in
            for remaining in stride(from: seconds, to: 0, by: -1) {
                self?.countdownHUD.update("\(remaining)")
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            guard let self else { return }
            countdownHUD.hide()
            countdown = nil
            // Give the window server a frame to drop the countdown before the screen freezes.
            try? await Task.sleep(for: .milliseconds(120))
            await app?.runAreaCapture(pressedAt: ContinuousClock.now, preset: id, enterAction: action)
        }
    }

    private func cancelCountdown() {
        countdown?.cancel()
        countdown = nil
        countdownHUD.hide()
        Log.write("countdown cancelled")
    }

    // MARK: - Live area and repeat

    private func toggleLivePicker(preset id: PresetID, action: CaptureAction) {
        if let livePicker {
            livePicker.cancel()
            return
        }
        guard app?.areaCaptureRunning == false else { return }
        guard Permissions.hasScreenCapture else { return Permissions.showMissingScreenCaptureAlert() }
        let picker = LiveAreaPicker(windows: WindowList.snapshot()) { [weak self] area in
            guard let self else { return }
            livePicker = nil
            guard let area else {
                Log.write("capture live area cancelled")
                return
            }
            remember(area: area)
            Task {
                // Let the clear panels leave the screen before the pixels are taken.
                try? await Task.sleep(for: .milliseconds(80))
                await self.capture(area, preset: id, action: action, label: "live")
            }
        }
        livePicker = picker
        picker.show()
    }

    /// The last area again, live and without picking. Before any area capture there is
    /// nothing to repeat, so it opens the area overlay instead.
    private func repeatLastArea(preset id: PresetID, action: CaptureAction) async {
        guard let area = settings.lastArea else {
            Log.write("repeat area: no area yet, opening the overlay")
            await app?.runAreaCapture(pressedAt: ContinuousClock.now, preset: id, enterAction: action)
            return
        }
        guard Permissions.hasScreenCapture else { return Permissions.showMissingScreenCaptureAlert() }
        await capture(area, preset: id, action: action, label: "repeat")
    }

    /// Takes `area` (Cocoa global points) off the live screen it sits on.
    private func capture(_ area: CGRect, preset id: PresetID, action: CaptureAction, label: String) async {
        guard app?.areaCaptureRunning == false else { return }
        let screens = NSScreen.screens
        guard let index = DisplayPicking.index(
            containing: CGPoint(x: area.midX, y: area.midY), in: screens.map(\.frame)
        ) else {
            Log.write("capture \(label): \(area) is on no display")
            Toast.show("That area isn’t on any screen now")
            NSSound.beep()
            return
        }
        let screen = screens[index]
        do {
            let capture = try await ScreenCapturer.capture([screen], excluding: delivery.thumbnails.windowNumbers)
            guard let display = capture.displays.first else { throw CaptureError.noDisplay }
            let local = area.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
            guard let rect = display.geometry.pixelRect(forView: local),
                  let image = display.image.cropping(to: rect.cgRect)
            else { throw CaptureError.noDisplay }
            delivery.deliver(
                image, scale: display.scale, on: screen, action: action,
                log: String(
                    format: "capture %@ %dx%d @%.0fx list=%.1fms grab=%.1fms", label,
                    image.width, image.height, display.scale,
                    capture.contentQuery.milliseconds, capture.grab.milliseconds
                ),
                preset: id
            )
        } catch {
            Log.write("capture \(label) failed: \(error)")
            NSSound.beep()
        }
    }
}
