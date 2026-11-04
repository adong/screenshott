import CoreGraphics
import Foundation
import ImageIO

/// Where re-editable projects live (decision 7a): one folder per exported PNG, named
/// after it, holding `project.json` and each capture's untouched pixels as
/// `<image id>.png`. The PNG in the save folder is always flattened; only this folder,
/// on this Mac, keeps what a pixelate covered.
public struct ProjectStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// ~/Library/Application Support/Screenshott/Projects
    public static let standard = ProjectStore(
        root: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Screenshott/Projects", isDirectory: true)
    )

    public enum Failure: Error, Equatable {
        /// Written by a newer Screenshott.
        case newerFormat(Int)
        case missingOriginal(UUID)
    }

    public struct Project: Sendable {
        public let document: EditorDocument
        /// Each capture's original PNG.
        public let originals: [UUID: URL]
    }

    /// "Screenshott 2026-11-02 at 09.41.27.png" → `<root>/Screenshott 2026-11-02 at 09.41.27/`
    public func folder(forPNGNamed name: String) -> URL {
        root.appendingPathComponent((name as NSString).deletingPathExtension, isDirectory: true)
    }

    /// Saves `document` for the PNG called `name`. `original` is asked for the PNG
    /// bytes of each capture whose original isn't in the folder yet; originals of
    /// captures no longer on the canvas are deleted.
    public func save(_ document: EditorDocument, forPNGNamed name: String, original: (UUID) -> Data?) throws {
        let folder = folder(forPNGNamed: name)
        let files = FileManager.default
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        for image in document.images {
            let url = originalURL(image.id, in: folder)
            guard !files.fileExists(atPath: url.path) else { continue }
            guard let data = original(image.id) else { throw Failure.missingOriginal(image.id) }
            try data.write(to: url, options: .atomic)
        }
        let kept = Set(document.images.map { originalURL($0.id, in: folder).lastPathComponent })
        for url in try files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        where url.pathExtension == "png" && UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil
            && !kept.contains(url.lastPathComponent) {
            try files.removeItem(at: url)
        }
        // A project opened from an older build is written in this build's format now.
        var document = document
        document.version = max(document.version, EditorDocument.formatVersion)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: folder.appendingPathComponent("project.json"), options: .atomic)
    }

    /// The project saved for the PNG called `name`, or nil when it was never edited.
    public func load(forPNGNamed name: String) throws -> Project? {
        let folder = folder(forPNGNamed: name)
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("project.json")) else { return nil }
        let document = try JSONDecoder().decode(EditorDocument.self, from: data)
        guard document.version <= EditorDocument.formatVersion else { throw Failure.newerFormat(document.version) }
        var originals: [UUID: URL] = [:]
        for image in document.images {
            let url = originalURL(image.id, in: folder)
            guard FileManager.default.fileExists(atPath: url.path) else { throw Failure.missingOriginal(image.id) }
            originals[image.id] = url
        }
        return Project(document: document, originals: originals)
    }

    private func originalURL(_ id: UUID, in folder: URL) -> URL {
        folder.appendingPathComponent("\(id.uuidString).png")
    }
}

public enum ImageFile {
    /// An image and its pixels per point, read from its DPI tag: 144 DPI is 2x, like
    /// the PNGs Screenshott writes. Untagged images count as 1x.
    public static func load(_ url: URL) -> (image: CGImage, scale: Double)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return load(source)
    }

    public static func load(_ data: Data) -> (image: CGImage, scale: Double)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return load(source)
    }

    private static func load(_ source: CGImageSource) -> (image: CGImage, scale: Double)? {
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = (properties?[kCGImagePropertyDPIWidth] as? Double) ?? 72
        return (image, clamp((dpi / 72).rounded(), 1, 3))
    }
}
