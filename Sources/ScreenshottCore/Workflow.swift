import Foundation

/// `workflow.json` at the root of a `.screenshottworkflow` bundle: a zip of this file,
/// the scripts it runs and an optional icon (#10). A workflow is a chain of steps that
/// runs after a capture, never before or during one (decision 10).
public struct WorkflowManifest: Equatable, Sendable {
    public static let fileName = "workflow.json"
    public static let fileExtension = "screenshottworkflow"
    public static let currentFormat = 1
    public static let defaultTimeout = 30
    public static let timeoutRange = 1...300

    public var format: Int
    /// Reverse-DNS style, e.g. `com.example.upload`; also the install folder's name.
    public var id: String
    public var name: String
    public var version: String
    public var author: String?
    public var summary: String?
    /// A PNG inside the bundle.
    public var icon: String?
    public var steps: [WorkflowStep]

    /// Relative paths of every script the workflow runs — what the install
    /// confirmation lists and what gets marked executable.
    public var scripts: [String] {
        steps.compactMap { if case .script(let path, _, _) = $0 { path } else { nil } }
    }

    /// Reads and checks a manifest. `fileExists` answers for paths relative to the
    /// bundle root, so the same check runs on an unpacked download and in tests.
    public static func load(_ data: Data, fileExists: (String) -> Bool) throws(WorkflowError) -> WorkflowManifest {
        let raw: Raw
        do {
            raw = try JSONDecoder().decode(Raw.self, from: data)
        } catch let DecodingError.typeMismatch(_, context), let DecodingError.valueNotFound(_, context) {
            let path = context.codingPath.map { $0.intValue.map { "#\($0 + 1)" } ?? $0.stringValue }
            throw .unreadable("wrong type at \(path.joined(separator: "."))")
        } catch {
            throw .unreadable("not valid JSON")
        }

        let format = raw.format ?? currentFormat
        guard format == currentFormat else { throw .unsupportedFormat(format) }
        guard let id = raw.id else { throw .missing("id") }
        guard isValidID(id) else { throw .invalidID(id) }
        guard let name = raw.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            throw .missing("name")
        }
        if let icon = raw.icon {
            guard isSafeRelativePath(icon) else { throw .pathOutsideBundle(icon) }
            guard fileExists(icon) else { throw .fileMissing(icon) }
        }
        guard let rawSteps = raw.steps, !rawSteps.isEmpty else { throw .noSteps }

        var steps: [WorkflowStep] = []
        for (index, step) in rawSteps.enumerated() {
            steps.append(try WorkflowStep(step, number: index + 1, fileExists: fileExists))
        }
        return WorkflowManifest(
            format: format, id: id, name: name, version: raw.version ?? "1.0", author: raw.author,
            summary: raw.description, icon: raw.icon, steps: steps
        )
    }

    /// Letters, digits, dot, dash and underscore, starting with a letter or digit — safe
    /// as a folder name and in a `workflow:<id>` preference.
    public static func isValidID(_ id: String) -> Bool {
        guard let first = id.unicodeScalars.first, id.count <= 100 else { return false }
        let alphanumerics = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        let allowed = alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        return alphanumerics.contains(first) && id.unicodeScalars.allSatisfy(allowed.contains)
    }

    /// A path that stays inside the bundle: relative, no `..`, no `~`.
    public static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~"), !path.contains("\0") else { return false }
        return !path.split(separator: "/", omittingEmptySubsequences: false).contains { $0 == ".." || $0.isEmpty }
    }

    private struct Raw: Decodable {
        var format: Int?
        var id: String?
        var name: String?
        var version: String?
        var author: String?
        var description: String?
        var icon: String?
        var steps: [RawStep]?
    }

    fileprivate struct RawStep: Decodable {
        var type: String?
        var path: String?
        var args: [String]?
        var timeout: Int?
        var name: String?
        var url: String?
        var action: String?
    }
}

public enum WorkflowStep: Equatable, Sendable {
    /// An executable file in the bundle, any language (it needs a `#!` line or to be a
    /// binary). Runs out of process with the capture on stdin; see `WorkflowInput`.
    case script(path: String, arguments: [String], timeout: Int)
    /// An Apple Shortcut from the user's library, given the PNG as input.
    case shortcut(name: String)
    /// A URL with `{placeholders}`; see `URLTemplate`.
    case openURL(template: String)
    case action(CaptureAction)

    fileprivate init(
        _ raw: WorkflowManifest.RawStep, number: Int, fileExists: (String) -> Bool
    ) throws(WorkflowError) {
        switch raw.type {
        case "script":
            guard let path = raw.path else { throw .missingStepField(step: number, "path") }
            guard WorkflowManifest.isSafeRelativePath(path) else { throw .pathOutsideBundle(path) }
            guard fileExists(path) else { throw .fileMissing(path) }
            let timeout = raw.timeout ?? WorkflowManifest.defaultTimeout
            guard WorkflowManifest.timeoutRange.contains(timeout) else {
                throw .timeoutOutOfRange(step: number, timeout)
            }
            self = .script(path: path, arguments: raw.args ?? [], timeout: timeout)
        case "shortcut":
            guard let name = raw.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
                throw .missingStepField(step: number, "name")
            }
            self = .shortcut(name: name)
        case "open-url":
            guard let url = raw.url else { throw .missingStepField(step: number, "url") }
            do {
                _ = try URLTemplate.expand(url, values: URLTemplate.sampleValues)
            } catch {
                throw .badURL(step: number, error.message)
            }
            self = .openURL(template: url)
        case "action":
            guard let name = raw.action else { throw .missingStepField(step: number, "action") }
            guard let action = CaptureAction(name: name), CaptureAction.workflowSteps.contains(action) else {
                throw .unknownAction(step: number, name)
            }
            self = .action(action)
        case let type?:
            throw .unknownStepType(step: number, type)
        case nil:
            throw .missingStepField(step: number, "type")
        }
    }

    /// One line of the install confirmation.
    public var description: String {
        switch self {
        case .script(let path, let arguments, _):
            "Run the script “\(([path] + arguments).joined(separator: " "))”"
        case .shortcut(let name): "Run the Shortcut “\(name)”"
        case .openURL(let template): "Open \(template)"
        case .action(let action):
            switch action {
            case .copyOnly: "Copy the image"
            case .save: "Save it to the screenshots folder"
            case .saveAs: "Ask where to save it"
            case .thumbnail: "Show the thumbnail"
            case .openEditor: "Open it in the editor"
            default: action.title
            }
        }
    }
}

public enum WorkflowError: Error, Equatable, Sendable {
    case unreadable(String)
    case unsupportedFormat(Int)
    case missing(String)
    case invalidID(String)
    case noSteps
    case unknownStepType(step: Int, String)
    case missingStepField(step: Int, String)
    case pathOutsideBundle(String)
    case fileMissing(String)
    case unknownAction(step: Int, String)
    case badURL(step: Int, String)
    case timeoutOutOfRange(step: Int, Int)

    public var message: String {
        switch self {
        case .unreadable(let why): "workflow.json can't be read: \(why)."
        case .unsupportedFormat(let format): "This workflow needs a newer Screenshott (format \(format))."
        case .missing(let field): "workflow.json has no “\(field)”."
        case .invalidID(let id): "“\(id)” isn't a valid id. Use letters, digits, dots and dashes."
        case .noSteps: "The workflow has no steps."
        case .unknownStepType(let step, let type): "Step \(step) has an unknown type “\(type)”."
        case .missingStepField(let step, let field): "Step \(step) needs a “\(field)”."
        case .pathOutsideBundle(let path): "“\(path)” points outside the workflow."
        case .fileMissing(let path): "“\(path)” isn't in the workflow."
        case .unknownAction(let step, let name):
            "Step \(step) names an unknown action “\(name)”. Known: "
                + CaptureAction.workflowSteps.map(\.name).joined(separator: ", ") + "."
        case .badURL(let step, let why): "Step \(step)’s URL: \(why)"
        case .timeoutOutOfRange(let step, let seconds):
            "Step \(step)’s timeout of \(seconds) s is outside \(WorkflowManifest.timeoutRange.lowerBound)–"
                + "\(WorkflowManifest.timeoutRange.upperBound) s."
        }
    }
}

/// `open-url` steps: `{name}` placeholders filled from the capture, each value
/// percent-encoded so it can't break out of its spot in the URL. `/` is left as is, so
/// `file://{path}` works and a path in a query stays readable.
public enum URLTemplate {
    public static let placeholders = ["path", "filename", "width", "height", "scale", "preset"]

    static let sampleValues = [
        "path": "/Users/me/Pictures/Screenshott/a b.png", "filename": "a b.png",
        "width": "100", "height": "50", "scale": "2", "preset": "captureArea",
    ]

    private static let allowed = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~/"
    )

    public enum Problem: Error, Equatable, Sendable {
        case unknownPlaceholder(String)
        case unclosedBrace
        case notAURL

        public var message: String {
            switch self {
            case .unknownPlaceholder(let name):
                "{\(name)} isn't a placeholder. Known: "
                    + URLTemplate.placeholders.map { "{\($0)}" }.joined(separator: ", ") + "."
            case .unclosedBrace: "a { has no closing }."
            case .notAURL: "it isn't a URL with a scheme (https:, file:, …)."
            }
        }
    }

    public static func expand(_ template: String, values: [String: String]) throws(Problem) -> URL {
        var result = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            result += rest[..<open]
            guard let close = rest[open...].firstIndex(of: "}") else { throw .unclosedBrace }
            let name = String(rest[rest.index(after: open)..<close])
            guard placeholders.contains(name) else { throw .unknownPlaceholder(name) }
            result += (values[name] ?? "").addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            rest = rest[rest.index(after: close)...]
        }
        result += rest
        guard let url = URL(string: result), let scheme = url.scheme, !scheme.isEmpty else { throw .notAURL }
        return url
    }
}
