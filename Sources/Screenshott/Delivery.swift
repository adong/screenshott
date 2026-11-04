import AppKit
import ScreenshottCore
import UniformTypeIdentifiers

/// One finished capture on its way through the after-capture actions.
@MainActor
final class CaptureItem {
    let image: CGImage
    let scale: CGFloat
    let screen: NSScreen?
    /// The preset that took it; nil for one reopened from a thumbnail.
    let preset: PresetID?
    let date = Date()
    /// Where it was saved, once an action saved it.
    var file: URL?
    private var encoded: Data?

    init(image: CGImage, scale: CGFloat, screen: NSScreen?, preset: PresetID?, file: URL? = nil) {
        self.image = image
        self.scale = scale
        self.screen = screen
        self.preset = preset
        self.file = file
    }

    /// The PNG, encoded on first use.
    var png: Data? {
        if encoded == nil { encoded = PNGEncoder.data(from: image, scale: scale) }
        return encoded
    }
}

/// What happens to a finished capture: the after-capture action interface. Every
/// built-in action runs through `run(_:on:)` — a preset's Enter, the overlay keys and
/// action bar, the thumbnail menu, a workflow's `action` steps — and an installed
/// workflow (#10) is one more kind of action.
@MainActor
final class Delivery {
    typealias Action = CaptureAction

    private static let shutterSound = NSSound(
        contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif",
        byReference: true
    )

    let thumbnails = Thumbnails()
    /// The bench swaps in a private pasteboard so it never touches the clipboard.
    var pasteboard = NSPasteboard.general
    /// The editor (M3), given the capture once it's saved. AppDelegate points it at `openInEditor`.
    var openEditor: ((CaptureItem) -> Void)?
    /// Installed workflows: (id, capture, log). AppDelegate points it at the WorkflowRunner.
    var runWorkflow: ((String, CaptureItem, String) -> Void)?
    /// The most recent capture.
    private(set) var last: CaptureItem?
    private let preferences: Preferences

    init(preferences: Preferences) {
        self.preferences = preferences
        thumbnails.onAction = { [weak self] action, item in self?.run(action, on: item, log: "thumbnail") }
    }

    /// A new capture: the shutter sound, the 1x downscale if Settings asked for it, then
    /// `action`. `log` starts the log line (what was captured and how long that took).
    func deliver(
        _ image: CGImage, scale: CGFloat, on screen: NSScreen?, action: Action, log: String, preset: PresetID? = nil
    ) {
        if preferences.playSound { Self.shutterSound?.play() }
        var image = image, scale = scale
        if !preferences.keepRetinaResolution, scale > 1, let logical = ImageScaling.downscaled(image, by: scale) {
            (image, scale) = (logical, 1)
        }
        let item = CaptureItem(image: image, scale: scale, screen: screen, preset: preset)
        last = item
        run(action, on: item, log: log)
    }

    /// Runs one action on a capture; this adds the encode and delivery timings and the
    /// file name to `log`.
    func run(_ action: Action, on item: CaptureItem, log: String) {
        switch action {
        case .workflow(let id):
            runWorkflow?(id, item, log)
            return
        default:
            break
        }
        let clock = ContinuousClock()
        let start = clock.now
        let encode = Perf.begin(.encode)
        let png = item.png
        Perf.end(encode)
        guard let png else {
            Log.write("\(log) encode failed")
            NSSound.beep()
            return
        }
        let encoded = clock.now
        let timings = String(format: "encode=%.1fms", (encoded - start).milliseconds)

        switch action {
        case .standard:
            let copySave = Perf.begin(.copySave)
            if preferences.copyToClipboard { copy(png) }
            do {
                let url = try save(item, png)
                Perf.end(copySave)
                Log.write(String(
                    format: "%@ %@ copy+save=%.1fms %@",
                    log, timings, (clock.now - encoded).milliseconds, url.lastPathComponent
                ))
                if preferences.showThumbnail { showThumbnail(item, file: url) }
            } catch {
                Log.write("\(log) save failed: \(error)")
                NSSound.beep()
            }
        case .copyOnly:
            copy(png)
            Log.write("\(log) \(timings) copied only")
        case .save, .thumbnail:
            do {
                let url = try save(item, png)
                Log.write("\(log) \(timings) \(action.name) \(url.lastPathComponent)")
                if action == .thumbnail { showThumbnail(item, file: url) }
            } catch {
                Log.write("\(log) save failed: \(error)")
                NSSound.beep()
            }
        case .saveAs:
            saveAs(item, png, log: "\(log) \(timings)")
        case .editor:
            // Saved, not copied: the editor's ⌘C and ⌘S deliver the marked-up version.
            do {
                let url = try save(item, png)
                Log.write("\(log) \(timings) saved \(url.lastPathComponent), opening the editor")
                openEditor?(item)
            } catch {
                Log.write("\(log) save failed: \(error)")
                NSSound.beep()
            }
        case .workflow:
            break
        }
    }

    private func copy(_ png: Data) {
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
    }

    /// Into the archive folder, once: an item that was already saved keeps its file.
    private func save(_ item: CaptureItem, _ png: Data) throws -> URL {
        if let file = item.file { return file }
        let directory = preferences.saveDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = ScreenshotNaming.uniqueURL(
            in: directory, fileName: ScreenshotNaming.fileName(for: item.date)
        ) { FileManager.default.fileExists(atPath: $0.path) }
        try png.write(to: url, options: .withoutOverwriting)
        item.file = url
        return url
    }

    private func showThumbnail(_ item: CaptureItem, file: URL) {
        thumbnails.show(item.image, scale: item.scale, file: file, on: item.screen)
    }

    private func saveAs(_ item: CaptureItem, _ png: Data, log: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = ScreenshotNaming.fileName(for: item.date)
        try? FileManager.default.createDirectory(at: preferences.saveDirectory, withIntermediateDirectories: true)
        panel.directoryURL = preferences.saveDirectory
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else {
            Log.write("\(log) save-as cancelled")
            return
        }
        do {
            try png.write(to: url)
            item.file = url
            Log.write("\(log) saved as \(url.path)")
            if preferences.showThumbnail { showThumbnail(item, file: url) }
        } catch {
            Log.write("\(log) save-as failed: \(error)")
            NSSound.beep()
        }
    }
}
