import Foundation

/// Append-only log at ~/Library/Logs/Screenshott.log, where a user can find it.
/// Also echoed to stderr so `swift run` shows it.
public enum Log {
    public static let url = FileManager.default
        .urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/Screenshott.log")

    public static func write(_ message: String) {
        let data = Data("\(Date().formatted(.iso8601)) \(message)\n".utf8)
        FileHandle.standardError.write(data)

        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try? data.write(to: url)
        }
    }
}

extension Duration {
    /// For timing logs: `(clock.now - start).milliseconds`.
    public var milliseconds: Double {
        Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
    }
}
