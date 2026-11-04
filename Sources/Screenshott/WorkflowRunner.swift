import AppKit
import ImageIO
import ScreenshottCore

/// Runs an installed workflow's steps in order on one capture. Scripts and Shortcuts
/// run out of process with responsibility disclaimed (see `Spawn`); a step's stdout
/// answer is applied before the next one starts, and the first failing step stops the
/// chain and says why.
@MainActor
final class WorkflowRunner {
    private let store: WorkflowStore
    private unowned let delivery: Delivery

    /// Each run's scratch folders live here; the next launch clears them.
    private static let scratch = FileManager.default.temporaryDirectory
        .appendingPathComponent("Screenshott Workflows", isDirectory: true)

    init(store: WorkflowStore, delivery: Delivery) {
        self.store = store
        self.delivery = delivery
        try? FileManager.default.removeItem(at: Self.scratch)
    }

    private struct StepFailure: Error {
        let message: String
    }

    /// Starts the run and returns it; its value is whether every step finished.
    @discardableResult
    func run(_ id: String, on item: CaptureItem, log: String) -> Task<Bool, Never>? {
        guard let workflow = store.workflow(id) else {
            Log.write("\(log) workflow \(id) isn't installed")
            Toast.show("The workflow “\(id)” isn’t installed")
            NSSound.beep()
            return nil
        }
        return Task { await run(workflow, on: item, log: log) }
    }

    private func run(_ workflow: InstalledWorkflow, on capture: CaptureItem, log: String) async -> Bool {
        let clock = ContinuousClock()
        let start = clock.now
        let label = "workflow \(workflow.id)"
        Log.write("\(log) → \(label) (\(workflow.manifest.steps.count) steps)")
        // Steps always get a file: the capture is archived first, as every capture is.
        delivery.run(.save, on: capture, log: "\(label) archive")
        guard capture.file != nil else {
            Toast.show("“\(workflow.name)” didn’t run", detail: "The capture couldn’t be saved")
            return false
        }

        let run = Self.scratch.appendingPathComponent(UUID().uuidString, isDirectory: true)
        var item = capture
        // What scripts see: the saved file, or the last image a step handed back.
        var imagePath = capture.file!.path
        for (index, step) in workflow.manifest.steps.enumerated() {
            let number = index + 1
            let output = run.appendingPathComponent("step-\(number)", isDirectory: true)
            let input = WorkflowInput(
                image: item.file?.path ?? imagePath, width: item.image.width, height: item.image.height,
                scale: Double(item.scale), preset: capture.preset?.rawValue, capturedAt: capture.date,
                workflow: workflow.id, step: number, outputDirectory: output.path
            )
            do {
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                let answer: WorkflowOutput
                switch step {
                case .action(let action):
                    delivery.run(action, on: item, log: "\(label) step \(number)")
                    continue
                case .openURL(let template):
                    let url: URL
                    do { url = try URLTemplate.expand(template, values: input.templateValues) } catch {
                        throw StepFailure(message: error.message)
                    }
                    Log.write("\(label) step \(number) open \(url.absoluteString)")
                    NSWorkspace.shared.open(url)
                    continue
                case .script(let path, let arguments, let timeout):
                    let executable = workflow.folder.appendingPathComponent(path).path
                    let result = try await spawn(
                        executable, arguments, environment: Self.environment.merging(input.environment) { $1 },
                        directory: workflow.folder.path, input: input.json, timeout: timeout
                    )
                    try check(result, what: path, timeout: timeout)
                    do { answer = try WorkflowOutput.parse(result.stdout) } catch {
                        throw StepFailure(message: "\(path) \(error.message)")
                    }
                case .shortcut(let name):
                    let file = output.appendingPathComponent("output")
                    let result = try await spawn(
                        "/usr/bin/shortcuts", ["run", name, "--input-path", input.image, "--output-path", file.path],
                        environment: Self.environment.merging(input.environment) { $1 },
                        directory: output.path, input: Data(), timeout: 120
                    )
                    try check(result, what: "The Shortcut “\(name)”", timeout: 120)
                    answer = try shortcutAnswer(file)
                }
                if !answer.ignored.isEmpty {
                    Log.write("\(label) step \(number) ignored keys: \(answer.ignored.joined(separator: ", "))")
                }
                if let replaced = try apply(answer, from: workflow, relativeTo: output) {
                    item = CaptureItem(image: replaced.image, scale: replaced.scale, screen: capture.screen, preset: capture.preset)
                    imagePath = replaced.path
                }
                Log.write("\(label) step \(number) ok")
            } catch let failure as StepFailure {
                fail(workflow, step: number, failure.message)
                return false
            } catch {
                fail(workflow, step: number, "\(error)")
                return false
            }
        }
        Log.write(String(format: "%@ done in %.0fms", label, (clock.now - start).milliseconds))
        return true
    }

    private func fail(_ workflow: InstalledWorkflow, step: Int, _ message: String) {
        Log.write("workflow \(workflow.id) step \(step) failed: \(message)")
        Toast.show("“\(workflow.name)” stopped at step \(step)", detail: message)
        NSSound.beep()
    }

    /// A minimal environment: the steps don't inherit whatever launched Screenshott.
    private static let environment: [String: String] = {
        let inherited = ProcessInfo.processInfo.environment
        var env = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin", "LANG": "en_US.UTF-8"]
        for key in ["HOME", "USER", "LOGNAME", "SHELL", "TMPDIR"] { env[key] = inherited[key] }
        env["SCREENSHOTT_VERSION"] = SigningInfo.version
        return env
    }()

    private func spawn(
        _ executable: String, _ arguments: [String], environment: [String: String], directory: String,
        input: Data, timeout: Int
    ) async throws -> Spawn.Result {
        try await Task.detached {
            try Spawn.run(
                executable, arguments: arguments, environment: environment, directory: directory,
                input: input, timeout: .seconds(timeout)
            )
        }.value
    }

    private func check(_ result: Spawn.Result, what: String, timeout: Int) throws {
        if result.timedOut { throw StepFailure(message: "\(what) took longer than \(timeout) s") }
        if let signal = result.signal { throw StepFailure(message: "\(what) was killed by signal \(signal)") }
        if let status = result.status, status != 0 {
            let line = result.errorLine
            throw StepFailure(message: "\(what) exited with \(status)\(line.isEmpty ? "" : ": \(line)")")
        }
    }

    /// A Shortcut answers with whatever its last action outputs: an image replaces the
    /// capture, a JSON object is read like a script's stdout, anything else is ignored.
    private func shortcutAnswer(_ file: URL) throws -> WorkflowOutput {
        guard let data = try? Data(contentsOf: file), !data.isEmpty else { return WorkflowOutput() }
        if Self.loadImage(file) != nil { return WorkflowOutput(image: file.path) }
        return (try? WorkflowOutput.parse(data)) ?? WorkflowOutput()
    }

    /// Does what a step asked. Returns the replacement image, if it handed one back.
    private func apply(
        _ answer: WorkflowOutput, from workflow: InstalledWorkflow, relativeTo output: URL
    ) throws -> (image: CGImage, scale: CGFloat, path: String)? {
        if let text = answer.clipboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        if let message = answer.notify { Toast.show(message, detail: workflow.name) }
        if let target = answer.open {
            if let url = URL(string: target), let scheme = url.scheme, scheme.count > 1 {
                NSWorkspace.shared.open(url)
            } else {
                NSWorkspace.shared.open(resolve(target, relativeTo: output))
            }
        }
        guard let path = answer.image else { return nil }
        let url = resolve(path, relativeTo: output)
        guard let (image, scale) = Self.loadImage(url) else {
            throw StepFailure(message: "the image it handed back, \(url.path), can’t be read")
        }
        return (image, scale, url.path)
    }

    private func resolve(_ path: String, relativeTo directory: URL) -> URL {
        path.hasPrefix("/") ? URL(fileURLWithPath: path) : directory.appendingPathComponent(path)
    }

    /// The image and its scale, from the DPI the file carries (144 → 2x).
    private static func loadImage(_ url: URL) -> (CGImage, CGFloat)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = properties?[kCGImagePropertyDPIWidth] as? Double ?? 72
        return (image, max(CGFloat(dpi / 72).rounded(), 1))
    }
}
