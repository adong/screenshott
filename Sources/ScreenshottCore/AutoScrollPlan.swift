/// Auto-scroll: how far to scroll next, and when to stop. One scroll at a time: the
/// app posts it, waits for the frames to settle, sums up what the stitcher made of them
/// and asks again.
///
/// It stops when two scrolls in a row move nothing (the bottom), when the stitch is
/// full, or when three scrolls in a row lose the overlap. Step sizes adapt: apps scale
/// scroll events their own way, so each step is sized from how far the last one really
/// moved the content, aiming at 60% of the rows that move (frame minus sticky bands).
public struct AutoScrollPlan: Sendable {
    public enum Outcome: Equatable, Sendable {
        /// The content moved up `pixels` rows; `body` rows of the region move with it.
        case moved(pixels: Int, body: Int)
        /// Nothing moved.
        case unchanged
        /// The content moved the wrong way.
        case backward
        /// The new frames don't overlap the last good one: that scroll went too far.
        case lost
        /// The stitch reached its height cap.
        case full

        /// What one scroll's frames add up to.
        public static func summarizing(_ steps: [ScrollStitcher.Step], body: Int) -> Outcome {
            var moved = 0, backward = false, lost = false
            for step in steps {
                switch step {
                case .appended(let shift): moved += shift
                case .full: return .full
                case .backward: backward = true
                case .lost: lost = true
                case .first, .unchanged: break
                }
            }
            if moved > 0 { return .moved(pixels: moved, body: body) }
            if lost { return .lost }
            return backward ? .backward : .unchanged
        }
    }

    public enum Stop: String, Sendable {
        case bottom, full, lost
    }

    public enum Action: Equatable, Sendable {
        /// Scroll by this many points; positive is further down the document.
        case scroll(points: Double)
        case stop(Stop)
    }

    static let targetShare = 0.6
    static let unchangedToStop = 2
    static let lostToStop = 3

    /// Pixels per point.
    private let scale: Double
    private let regionHeight: Int
    private var body: Int
    private var share = AutoScrollPlan.targetShare
    /// Rows the content moves per pixel of scroll we post; 1 for most apps.
    private var gain = 1.0
    private var lastPoints = 0.0
    private var unchanged = 0
    private var lost = 0
    /// The scroll just posted undoes a bad one, so what it shows says nothing.
    private var recovering = false
    /// Set when scrolling "down" moved the content down: the app reads the wheel the
    /// other way round, so the caller flips the sign from now on.
    public private(set) var inverted = false

    public init(regionHeight: Int, scale: Double) {
        self.regionHeight = regionHeight
        self.scale = max(scale, 1)
        body = regionHeight
    }

    /// How many rows `points` of scroll should move the content, going by the last
    /// step — the hint `OverlapSearch` uses when rows repeat.
    public func expectedShift(for points: Double) -> Int {
        Int((points * gain * scale).rounded())
    }

    /// The first scroll: half the region, since the sticky bands are still unknown.
    public mutating func start() -> Action {
        lastPoints = points(for: 0.5 * Double(regionHeight))
        return .scroll(points: lastPoints)
    }

    public mutating func next(after outcome: Outcome) -> Action {
        if outcome == .full { return .stop(.full) }
        if recovering {
            recovering = false
            return forward()
        }
        switch outcome {
        case .moved(let pixels, let body):
            unchanged = 0
            lost = 0
            if lastPoints > 0 {
                let observed = Double(pixels) / (lastPoints * scale)
                gain = min(max(observed, 0.05), 20)
            }
            self.body = max(body, 1)
            share = min(Self.targetShare, share * 1.5)
            return forward()
        case .unchanged:
            unchanged += 1
            return unchanged >= Self.unchangedToStop ? .stop(.bottom) : .scroll(points: lastPoints)
        case .backward:
            guard !inverted else { return lostOverlap() }
            inverted = true
            recovering = true
            // With the sign flipped, the same scroll undoes the wrong-way one.
            return .scroll(points: lastPoints)
        case .lost:
            return lostOverlap()
        case .full:
            return .stop(.full)
        }
    }

    private mutating func lostOverlap() -> Action {
        lost += 1
        if lost >= Self.lostToStop { return .stop(.lost) }
        share /= 2
        recovering = true
        return .scroll(points: -lastPoints)
    }

    private mutating func forward() -> Action {
        lastPoints = points(for: share * Double(body))
        return .scroll(points: lastPoints)
    }

    /// Points to scroll to move the content `pixels` rows, never more than the region.
    private func points(for pixels: Double) -> Double {
        let points = pixels / (gain * scale)
        return min(max(points, 4), Double(regionHeight) / scale).rounded()
    }
}
