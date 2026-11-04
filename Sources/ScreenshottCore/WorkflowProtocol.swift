import Foundation

/// What a script step is told about the capture: the same fields as JSON on stdin and
/// as `SCREENSHOTT_*` environment variables, so a one-line shell script needs no JSON
/// parser.
public struct WorkflowInput: Codable, Equatable, Sendable {
    /// Absolute path of the PNG. After a step answered `image`, the new one.
    public var image: String
    public var width: Int
    public var height: Int
    /// 2 for a full-resolution capture from a Retina display.
    public var scale: Double
    /// The preset that took the capture, nil when a workflow ran from the menu.
    public var preset: String?
    /// ISO 8601.
    public var capturedAt: String
    public var workflow: String
    /// 1-based.
    public var step: Int
    /// An empty folder the step may write a replacement image into.
    public var outputDirectory: String

    public init(
        image: String, width: Int, height: Int, scale: Double, preset: String?, capturedAt: Date,
        workflow: String, step: Int, outputDirectory: String
    ) {
        self.image = image
        self.width = width
        self.height = height
        self.scale = scale
        self.preset = preset
        self.capturedAt = capturedAt.formatted(.iso8601)
        self.workflow = workflow
        self.step = step
        self.outputDirectory = outputDirectory
    }

    public var json: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)) ?? Data("{}".utf8)
    }

    public var environment: [String: String] {
        var env = [
            "SCREENSHOTT_IMAGE": image,
            "SCREENSHOTT_WIDTH": String(width),
            "SCREENSHOTT_HEIGHT": String(height),
            "SCREENSHOTT_SCALE": Self.number(scale),
            "SCREENSHOTT_CAPTURED_AT": capturedAt,
            "SCREENSHOTT_WORKFLOW": workflow,
            "SCREENSHOTT_STEP": String(step),
            "SCREENSHOTT_OUTPUT_DIR": outputDirectory,
        ]
        if let preset { env["SCREENSHOTT_PRESET"] = preset }
        return env
    }

    /// Values for an `open-url` step's placeholders.
    public var templateValues: [String: String] {
        [
            "path": image, "filename": (image as NSString).lastPathComponent,
            "width": String(width), "height": String(height), "scale": Self.number(scale), "preset": preset ?? "",
        ]
    }

    /// "2", not "2.0".
    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

/// What a step prints on stdout: nothing, or one JSON object telling the app what to do
/// next. Logs belong on stderr.
///
///     {"clipboard": "text", "notify": "Done", "open": "https://…", "image": "/path/new.png"}
public struct WorkflowOutput: Equatable, Sendable {
    /// Text to put on the clipboard.
    public var clipboard: String?
    /// A short message to show.
    public var notify: String?
    /// A URL or file path to open.
    public var open: String?
    /// A replacement image for the next steps: absolute, or relative to the output folder.
    public var image: String?
    /// Keys this version doesn't know, logged so a typo shows up.
    public var ignored: [String] = []

    public static let keys = ["clipboard", "notify", "open", "image"]

    public init(clipboard: String? = nil, notify: String? = nil, open: String? = nil, image: String? = nil) {
        self.clipboard = clipboard
        self.notify = notify
        self.open = open
        self.image = image
    }

    public enum Problem: Error, Equatable, Sendable {
        case notAnObject(String)
        case notAString(String)

        public var message: String {
            switch self {
            case .notAnObject(let start):
                "printed “\(start)”, but stdout must be empty or one JSON object (logs go to stderr)"
            case .notAString(let key): "“\(key)” must be a string"
            }
        }
    }

    public static func parse(_ data: Data) throws(Problem) -> WorkflowOutput {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return WorkflowOutput() }
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw .notAnObject(String(text.prefix(40)))
        }
        func string(_ key: String) throws(Problem) -> String? {
            switch object[key] {
            case nil, is NSNull: return nil
            case let value as String: return value
            default: throw .notAString(key)
            }
        }
        var output = WorkflowOutput(
            clipboard: try string("clipboard"), notify: try string("notify"),
            open: try string("open"), image: try string("image")
        )
        output.ignored = object.keys.filter { !keys.contains($0) }.sorted()
        return output
    }
}
