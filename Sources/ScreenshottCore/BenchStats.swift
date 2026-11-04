import Foundation

/// p50 / p95 of one stage's timings for `--bench`, in milliseconds. Nearest-rank
/// percentiles: always one of the samples, never an average of two, so a p95 is a
/// capture that really took that long.
public struct BenchStats: Equatable, Sendable {
    public let count: Int
    public let p50: Double
    public let p95: Double
    public let min: Double
    public let max: Double

    public init?(_ samples: [Double]) {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        count = sorted.count
        p50 = Self.percentile(50, of: sorted)
        p95 = Self.percentile(95, of: sorted)
        min = sorted[0]
        max = sorted[sorted.count - 1]
    }

    /// The ⌈p / 100 × n⌉-th smallest of `sorted`.
    static func percentile(_ p: Double, of sorted: [Double]) -> Double {
        let rank = Int((p / 100 * Double(sorted.count)).rounded(.up))
        return sorted[Swift.min(Swift.max(rank, 1), sorted.count) - 1]
    }

    /// `p50=27.1 p95=33.0 (min 19.4, max 35.2, n=20)`
    public var summary: String {
        String(format: "p50=%.1f p95=%.1f (min %.1f, max %.1f, n=%d)", p50, p95, min, max, count)
    }
}
