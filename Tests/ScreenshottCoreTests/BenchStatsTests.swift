import Testing
@testable import ScreenshottCore

@Test func percentilesAreNearestRank() {
    let stats = BenchStats((1...20).map(Double.init))
    #expect(stats?.p50 == 10)
    #expect(stats?.p95 == 19)
    #expect(stats?.min == 1)
    #expect(stats?.max == 20)
    #expect(stats?.count == 20)
}

@Test func orderOfSamplesDoesNotMatter() {
    #expect(BenchStats([40, 10, 30, 20]) == BenchStats([10, 20, 30, 40]))
    #expect(BenchStats([40, 10, 30, 20])?.p50 == 20)
}

@Test func smallRunsReportTheSlowestAsP95() {
    #expect(BenchStats([5, 1, 9, 3, 7, 2, 8, 4, 6, 10])?.p95 == 10)
    let one = BenchStats([42])
    #expect(one?.p50 == 42)
    #expect(one?.p95 == 42)
}

@Test func noSamplesNoStats() {
    #expect(BenchStats([]) == nil)
}

@Test func summaryIsMilliseconds() {
    #expect(BenchStats([12.34, 56.78])?.summary == "p50=12.3 p95=56.8 (min 12.3, max 56.8, n=2)")
}
