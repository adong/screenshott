import Foundation

public enum ScreenshotNaming {
    /// "Screenshott 2026-11-01 at 17.47.03.png" — sorts by time in Finder, and uses
    /// dots instead of colons because Finder shows ":" as "/".
    public static func fileName(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshott \(formatter.string(from: date)).png"
    }

    /// Two captures in the same second would share a name, so append " (2)", " (3)"…
    /// until `exists` reports a free one.
    public static func uniqueURL(in directory: URL, fileName: String, exists: (URL) -> Bool) -> URL {
        let first = directory.appendingPathComponent(fileName)
        guard exists(first) else { return first }

        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var n = 2
        while true {
            let candidate = directory.appendingPathComponent("\(base) (\(n)).\(ext)")
            if !exists(candidate) { return candidate }
            n += 1
        }
    }
}
