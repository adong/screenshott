import AppKit
import ScreenshottCore
import UniformTypeIdentifiers

/// One installed workflow: its manifest and the folder it was unpacked into.
struct InstalledWorkflow: Identifiable, Equatable {
    let manifest: WorkflowManifest
    let folder: URL

    var id: String { manifest.id }
    var name: String { manifest.name }

    var icon: NSImage? {
        manifest.icon.flatMap { NSImage(contentsOf: folder.appendingPathComponent($0)) }
    }
}

/// The workflows in `~/Library/Application Support/Screenshott/Workflows/`, one folder
/// per workflow id. A `.screenshottworkflow` (a zip) installs by double-click, after a
/// confirmation that lists everything it will run.
@MainActor
final class WorkflowStore: ObservableObject {
    static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Screenshott/Workflows", isDirectory: true)

    @Published private(set) var installed: [InstalledWorkflow] = []

    /// For the README shots: only the example workflows, never what Alan installed.
    var examplesOnly = false {
        didSet { reload() }
    }

    init() {
        reload()
    }

    var ids: Set<String> { Set(installed.map(\.id)) }

    func workflow(_ id: String) -> InstalledWorkflow? { installed.first { $0.id == id } }

    func reload() {
        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(
            at: Self.folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        )) ?? []
        var found: [InstalledWorkflow] = []
        for folder in folders {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(WorkflowManifest.fileName)) else {
                continue
            }
            do {
                let manifest = try WorkflowManifest.load(data) { fm.fileExists(atPath: folder.appendingPathComponent($0).path) }
                guard !examplesOnly || manifest.id.hasPrefix("com.screenshott.example.") else { continue }
                found.append(InstalledWorkflow(manifest: manifest, folder: folder))
            } catch {
                Log.write("workflow \(folder.lastPathComponent) skipped: \(error.message)")
            }
        }
        installed = found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Install

    /// Unpacks `url` (a `.screenshottworkflow` zip, or an unpacked bundle folder), checks
    /// it, asks, and installs it — replacing an older copy with the same id.
    func install(from url: URL) {
        let fm = FileManager.default
        var scratch: URL?
        defer { if let scratch { try? fm.removeItem(at: scratch) } }
        do {
            try fm.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            let root: URL
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                root = url
            } else {
                // Same volume as the install folder, so the final move is a rename.
                let temp = try fm.url(
                    for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: Self.folder, create: true
                )
                scratch = temp
                try unzip(url, into: temp)
                root = try bundleRoot(in: temp)
            }
            let manifest = try WorkflowManifest.load(Data(contentsOf: root.appendingPathComponent(WorkflowManifest.fileName))) {
                fm.fileExists(atPath: root.appendingPathComponent($0).path)
            }
            try checkNoLinksOut(of: root, manifest: manifest)

            let existing = workflow(manifest.id)
            guard confirm(manifest, icon: manifest.icon.flatMap { NSImage(contentsOf: root.appendingPathComponent($0)) },
                          replacing: existing)
            else {
                Log.write("workflow install cancelled: \(manifest.id)")
                return
            }

            let destination = Self.folder.appendingPathComponent(manifest.id, isDirectory: true)
            if fm.fileExists(atPath: destination.path) { try fm.trashItem(at: destination, resultingItemURL: nil) }
            if scratch != nil { try fm.moveItem(at: root, to: destination) } else { try fm.copyItem(at: root, to: destination) }
            prepare(destination, manifest: manifest)
            reload()
            Log.write("workflow installed: \(manifest.id) \(manifest.version) from \(url.lastPathComponent)")
            Toast.show("Installed “\(manifest.name)”", detail: "Pick it in Settings, the overlay or a thumbnail")
        } catch {
            let message = (error as? WorkflowError)?.message ?? (error as? InstallError)?.message
                ?? error.localizedDescription
            Log.write("workflow install failed: \(url.lastPathComponent): \(message)")
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "“\(url.deletingPathExtension().lastPathComponent)” can’t be installed"
            alert.informativeText = message
            NSApp.activate()
            alert.runModal()
        }
    }

    /// Moves it to the Trash, so a removal can be undone from Finder.
    func remove(_ workflow: InstalledWorkflow) {
        do {
            try FileManager.default.trashItem(at: workflow.folder, resultingItemURL: nil)
            Log.write("workflow removed: \(workflow.id)")
        } catch {
            Log.write("workflow remove failed: \(workflow.id): \(error)")
            NSSound.beep()
        }
        reload()
    }

    func openFolder() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Self.folder)
    }

    /// An open panel for `.screenshottworkflow` files, for the menu and Settings.
    func chooseAndInstall() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: WorkflowManifest.fileExtension) ?? .zip]
        panel.prompt = "Install"
        NSApp.activate()
        if panel.runModal() == .OK, let url = panel.url { install(from: url) }
    }

    private enum InstallError: Error {
        case unzip(String)
        case noManifest

        var message: String {
            switch self {
            case .unzip(let why): "It isn’t a readable zip: \(why)"
            case .noManifest: "There’s no workflow.json at the top of it."
            }
        }
    }

    private func unzip(_ archive: URL, into directory: URL) throws {
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", archive.path, directory.path]
        let errors = Pipe()
        ditto.standardError = errors
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else {
            let why = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw InstallError.unzip(why.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Zipping a folder in Finder puts everything one level down, so accept the
    /// manifest at the top or inside a single top-level folder.
    private func bundleRoot(in directory: URL) throws -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: directory.appendingPathComponent(WorkflowManifest.fileName).path) { return directory }
        let children = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let folders = children.filter { $0.hasDirectoryPath && $0.lastPathComponent != "__MACOSX" }
        if folders.count == 1, fm.fileExists(atPath: folders[0].appendingPathComponent(WorkflowManifest.fileName).path) {
            return folders[0]
        }
        throw InstallError.noManifest
    }

    /// The manifest's paths are already relative with no `..`; this catches a symlink
    /// in the zip that points out of the bundle.
    private func checkNoLinksOut(of root: URL, manifest: WorkflowManifest) throws {
        let base = root.resolvingSymlinksInPath().path + "/"
        for path in manifest.scripts + [manifest.icon].compactMap({ $0 }) {
            let resolved = root.appendingPathComponent(path).resolvingSymlinksInPath().path
            guard resolved.hasPrefix(base) else { throw WorkflowError.pathOutsideBundle(path) }
        }
    }

    /// Scripts become executable (zips made by some tools drop the bit), and the
    /// download quarantine is lifted: the user just approved exactly these scripts.
    private func prepare(_ folder: URL, manifest: WorkflowManifest) {
        for script in manifest.scripts {
            chmod(folder.appendingPathComponent(script).path, 0o755)
        }
        let paths = FileManager.default.enumerator(atPath: folder.path)?.compactMap { $0 as? String } ?? []
        for path in [""] + paths {
            removexattr(folder.appendingPathComponent(path).path, "com.apple.quarantine", XATTR_NOFOLLOW)
        }
    }

    /// The install confirmation: who made it and every step it will run.
    private func confirm(_ manifest: WorkflowManifest, icon: NSImage?, replacing existing: InstalledWorkflow?) -> Bool {
        let alert = NSAlert()
        alert.messageText = existing == nil
            ? "Install the workflow “\(manifest.name)”?"
            : "Replace “\(manifest.name)” \(existing?.manifest.version ?? "") with version \(manifest.version)?"
        var lines: [String] = []
        if let summary = manifest.summary { lines.append(summary) }
        lines.append("By \(manifest.author ?? "an unknown author") · version \(manifest.version)")
        lines.append("")
        lines.append("After a capture you run it on, it will:")
        lines += manifest.steps.map { "•  \($0.description)" }
        if !manifest.scripts.isEmpty {
            lines.append("")
            lines.append("""
                Scripts run as you and can read and change your files. They don’t get \
                Screenshott’s Screen Recording permission. Only install workflows you trust.
                """)
        }
        alert.informativeText = lines.joined(separator: "\n")
        if let icon { alert.icon = icon }
        alert.addButton(withTitle: existing == nil ? "Install" : "Replace")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}
