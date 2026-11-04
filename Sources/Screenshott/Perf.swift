import os

/// Stage timings (M6). Every stage of a capture is an os_signpost interval in the
/// com.adong.Screenshott subsystem. Signposts aren't kept for `log show`; watch them live
/// with `log stream --signpost --predicate 'subsystem == "com.adong.Screenshott"'`.
/// While `--bench` records, each duration is also kept for its p50 / p95 report.
@MainActor
enum Perf {
    enum Stage: String, CaseIterable {
        case windowList = "window list"
        case contentList = "content list"
        case grab
        case encode
        case copySave = "copy+save"

        /// Signpost names have to be static strings.
        var name: StaticString {
            switch self {
            case .windowList: "window list"
            case .contentList: "content list"
            case .grab: "grab"
            case .encode: "encode"
            case .copySave: "copy+save"
            }
        }
    }

    struct Span {
        fileprivate let stage: Stage
        fileprivate let state: OSSignpostIntervalState
        fileprivate let start: ContinuousClock.Instant
    }

    private static let signposter = OSSignposter(subsystem: "com.adong.Screenshott", category: "capture")

    /// Durations by stage while the bench records; nil the rest of the time.
    static var samples: [Stage: [Duration]]?

    static func begin(_ stage: Stage) -> Span {
        let state = signposter.beginInterval(stage.name, id: signposter.makeSignpostID())
        return Span(stage: stage, state: state, start: .now)
    }

    @discardableResult
    static func end(_ span: Span) -> Duration {
        let elapsed = ContinuousClock.now - span.start
        signposter.endInterval(span.stage.name, span.state)
        samples?[span.stage, default: []].append(elapsed)
        return elapsed
    }
}
