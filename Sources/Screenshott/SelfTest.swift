import AppKit
import ScreenshottCore

/// `open dist/Screenshott.app --args --self-test` clicks through what M2 and M7 add,
/// without a mouse: Delayed Area (countdown, overlay, Enter), Repeat Last Area, and the
/// example workflows Copy Markdown Link and Copy at 1x on the result. It logs
/// `self-test PASS|FAIL <check>: <detail>` for each and quits; scripts/self-test.sh runs
/// it and prints the lines. Live Area needs a real drag, so it isn't covered. A normal
/// launch never gets here.
///
/// Everything happens over the README shots' stock wallpaper. Side effects: the shutter
/// sound, the clipboard, and a few captures of the wallpaper in the screenshots folder.
/// The remembered last area is put back afterwards.
@MainActor
enum SelfTest {
    static var requested: Bool { ProcessInfo.processInfo.arguments.contains("--self-test") }

    /// Polls `value` until it has one or `timeout` passes.
    static func wait<T>(_ timeout: Duration, for value: () -> T?) async -> T? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let found = value() { return found }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return value()
    }

    static let copyMarkdownLink = "com.screenshott.example.copy-markdown-link"
    static let halfSize = "com.screenshott.example.half-size"
}

extension AppDelegate {
    func runSelfTest() async {
        // Let the launch settle (status item placed, permission state read).
        try? await Task.sleep(for: .seconds(1.5))
        guard let stage = ScreenCapturer.screenUnderMouse ?? NSScreen.screens.first else { return }
        let backdrop = ReadmeShots.backdrop(on: stage)
        let savedArea = presets.settings.lastArea
        var failures = 0
        func report(_ check: String, _ passed: Bool, _ detail: String) {
            if !passed { failures += 1 }
            Log.write("self-test \(passed ? "PASS" : "FAIL") \(check): \(detail)")
        }
        defer {
            presets.settings.lastArea = savedArea
            backdrop.orderOut(nil)
            Log.write("self-test done, \(failures) failed")
            NSApp.terminate(nil)
        }
        try? await Task.sleep(for: .milliseconds(400))

        // 1. Delayed Area: the countdown, then the frozen overlay; Enter runs its action.
        let delay = presets.settings.delay(for: .delayedArea)
        let pressed = ContinuousClock.now
        let before = delivery.last
        presets.run(.delayedArea)
        guard let overlay = await SelfTest.wait(.seconds(delay + 5), for: { overlay }) else {
            return report("delayed-area", false, "no overlay \(delay + 5) s after the hotkey")
        }
        let waited = ContinuousClock.now - pressed
        _ = overlay.stageForReadme()
        try? await Task.sleep(for: .milliseconds(300))
        overlay.confirm(overlay.enterAction)
        guard let first = await SelfTest.wait(.seconds(3), for: { delivery.last.flatMap { $0 !== before ? $0 : nil } })
        else {
            return report("delayed-area", false, "Enter delivered nothing")
        }
        report(
            "delayed-area", first.preset == .delayedArea && waited >= .seconds(delay),
            String(
                format: "overlay after %.1f s (countdown %d s), %dx%d, %@", waited.milliseconds / 1000, delay,
                first.image.width, first.image.height, first.file?.lastPathComponent ?? "not saved"
            )
        )

        // 2. Repeat Last Area: the same rectangle again, live, nothing to pick.
        try? await Task.sleep(for: .milliseconds(800))
        presets.run(.repeatArea)
        if let repeated = await SelfTest.wait(.seconds(3), for: { delivery.last.flatMap { $0 !== first ? $0 : nil } }) {
            let same = repeated.image.width == first.image.width && repeated.image.height == first.image.height
            report(
                "repeat-area", repeated.preset == .repeatArea && same,
                "\(repeated.image.width)x\(repeated.image.height), \(repeated.file?.lastPathComponent ?? "not saved")"
            )
        } else {
            report("repeat-area", false, "nothing captured within 3 s")
        }

        // 3. The example workflows, on the delayed capture.
        let pasteboard = NSPasteboard.general
        if let run = workflowRunner.run(SelfTest.copyMarkdownLink, on: first, log: "self-test") {
            let finished = await run.value
            let text = pasteboard.string(forType: .string) ?? ""
            let file = first.file?.lastPathComponent ?? "?"
            report("workflow copy-markdown-link", finished && text.hasPrefix("![\(file)]("), "clipboard: \(text)")
        } else {
            report("workflow copy-markdown-link", false, "not installed; double-click dist/workflows/copy-markdown-link.screenshottworkflow")
        }
        if let run = workflowRunner.run(SelfTest.halfSize, on: first, log: "self-test") {
            let finished = await run.value
            let expected = Int((CGFloat(first.image.width) / first.scale).rounded(.down))
            let copied = pasteboard.data(forType: .png).flatMap { NSBitmapImageRep(data: $0) }?.pixelsWide
            report(
                "workflow half-size", finished && copied == expected,
                "copied \(copied.map(String.init) ?? "no PNG") px wide, expected \(expected) (capture \(first.image.width) @\(Int(first.scale))x)"
            )
        } else {
            report("workflow half-size", false, "not installed; double-click dist/workflows/half-size.screenshottworkflow")
        }
        // The same pixels as if from a Retina screen, so the resize path runs on a 1x display too.
        let retina = CaptureItem(image: first.image, scale: 2, screen: first.screen, preset: .delayedArea)
        if let run = workflowRunner.run(SelfTest.halfSize, on: retina, log: "self-test 2x") {
            let finished = await run.value
            let copied = pasteboard.data(forType: .png).flatMap { NSBitmapImageRep(data: $0) }
            let expected = retina.image.width / 2
            report(
                "workflow half-size 2x", finished && copied?.pixelsWide == expected && copied?.size.width == CGFloat(expected),
                "copied \(copied.map { "\($0.pixelsWide) px, \(Int($0.size.width)) pt" } ?? "no PNG"), expected \(expected)"
            )
        }
    }
}
