import AppKit
import ScreenshottCore
import UniformTypeIdentifiers

/// What happens to a finished capture. M2 turns this into the action interface that
/// the built-in actions and #10 workflows share.
@MainActor
final class Delivery {
    enum Action {
        /// Save to the folder; copy and show a thumbnail unless Settings turned them off.
        case standard
        case copyOnly
        /// A save panel instead of the archive folder.
        case saveAs
    }

    private static let shutterSound = NSSound(
        contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif",
        byReference: true
    )

    let thumbnails = Thumbnails()
    /// The bench swaps in a private pasteboard so it never touches the clipboard.
    var pasteboard = NSPasteboard.general
    private let preferences: Preferences

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    /// `log` starts the log line (what was captured and how long that took); this adds
    /// the encode and delivery timings and the file name.
    func deliver(_ image: CGImage, scale: CGFloat, on screen: NSScreen?, action: Action, log: String) {
        if preferences.playSound { Self.shutterSound?.play() }
        var image = image, scale = scale
        if !preferences.keepRetinaResolution, scale > 1, let logical = ImageScaling.downscaled(image, by: scale) {
            (image, scale) = (logical, 1)
        }
        let clock = ContinuousClock()
        let start = clock.now
        let encode = Perf.begin(.encode)
        let png = PNGEncoder.data(from: image, scale: scale)
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
                let url = try save(png)
                Perf.end(copySave)
                Log.write(String(
                    format: "%@ %@ copy+save=%.1fms %@",
                    log, timings, (clock.now - encoded).milliseconds, url.lastPathComponent
                ))
                if preferences.showThumbnail { thumbnails.show(image, scale: scale, file: url, on: screen) }
            } catch {
                Log.write("\(log) save failed: \(error)")
                NSSound.beep()
            }
        case .copyOnly:
            copy(png)
            Log.write("\(log) \(timings) copied only")
        case .saveAs:
            saveAs(png, image: image, scale: scale, on: screen, log: "\(log) \(timings)")
        }
    }

    private func copy(_ png: Data) {
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
    }

    private func save(_ png: Data) throws -> URL {
        let directory = preferences.saveDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = ScreenshotNaming.uniqueURL(
            in: directory, fileName: ScreenshotNaming.fileName(for: Date())
        ) { FileManager.default.fileExists(atPath: $0.path) }
        try png.write(to: url, options: .withoutOverwriting)
        return url
    }

    private func saveAs(_ png: Data, image: CGImage, scale: CGFloat, on screen: NSScreen?, log: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = ScreenshotNaming.fileName(for: Date())
        try? FileManager.default.createDirectory(at: preferences.saveDirectory, withIntermediateDirectories: true)
        panel.directoryURL = preferences.saveDirectory
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else {
            Log.write("\(log) save-as cancelled")
            return
        }
        do {
            try png.write(to: url)
            Log.write("\(log) saved as \(url.path)")
            if preferences.showThumbnail { thumbnails.show(image, scale: scale, file: url, on: screen) }
        } catch {
            Log.write("\(log) save-as failed: \(error)")
            NSSound.beep()
        }
    }
}
