import Testing
@testable import ScreenshottCore

@Test func firstScrollIsHalfTheRegion() {
    var plan = AutoScrollPlan(regionHeight: 1000, scale: 2)
    #expect(plan.start() == .scroll(points: 250))
}

@Test func twoScrollsThatMoveNothingMeanTheBottom() {
    var plan = AutoScrollPlan(regionHeight: 1000, scale: 2)
    _ = plan.start()
    #expect(plan.next(after: .unchanged) == .scroll(points: 250))
    #expect(plan.next(after: .unchanged) == .stop(.bottom))
}

@Test func movementInBetweenResetsTheBottomCount() {
    var plan = AutoScrollPlan(regionHeight: 1000, scale: 2)
    _ = plan.start()
    _ = plan.next(after: .unchanged)
    _ = plan.next(after: .moved(pixels: 500, body: 1000))
    if case .stop = plan.next(after: .unchanged) { Issue.record("stopped after one still scroll") }
}

@Test func stepsFollowHowFarTheAppReallyScrolls() {
    // This app moves the content twice as far as asked, and has 200 sticky rows.
    var plan = AutoScrollPlan(regionHeight: 1000, scale: 2)
    #expect(plan.start() == .scroll(points: 250))
    // 60% of the 800 moving rows, at 2 rows per pixel and 2 pixels per point.
    #expect(plan.next(after: .moved(pixels: 1000, body: 800)) == .scroll(points: 120))
    #expect(plan.expectedShift(for: 120) == 480)
}

@Test func aStepIsNeverLargerThanTheRegion() {
    var plan = AutoScrollPlan(regionHeight: 600, scale: 1)
    _ = plan.start()
    // A sluggish app: 300 points moved the content 15 rows.
    #expect(plan.next(after: .moved(pixels: 15, body: 600)) == .scroll(points: 600))
}

@Test func aLostOverlapScrollsBackAndTakesSmallerSteps() {
    var plan = AutoScrollPlan(regionHeight: 1000, scale: 1)
    #expect(plan.start() == .scroll(points: 500))
    #expect(plan.next(after: .lost) == .scroll(points: -500))
    // Whatever the scroll back shows, the next step is half the usual 60%.
    #expect(plan.next(after: .unchanged) == .scroll(points: 300))
    #expect(plan.next(after: .lost) == .scroll(points: -300))
    _ = plan.next(after: .moved(pixels: 0, body: 1000))
    let step = plan.next(after: .lost)
    #expect(step == .stop(.lost))
}

@Test func aWrongWayScrollFlipsTheWheel() {
    var plan = AutoScrollPlan(regionHeight: 1000, scale: 1)
    _ = plan.start()
    #expect(!plan.inverted)
    #expect(plan.next(after: .backward) == .scroll(points: 500))
    #expect(plan.inverted)
    // The undo shows nothing new; it is not counted toward the bottom.
    #expect(plan.next(after: .unchanged) == .scroll(points: 600))
    #expect(plan.next(after: .unchanged) == .scroll(points: 600))
}

@Test func aFullStitchStops() {
    var plan = AutoScrollPlan(regionHeight: 1000, scale: 1)
    _ = plan.start()
    #expect(plan.next(after: .full) == .stop(.full))
}

@Test func oneScrollsStepsAddUp() {
    typealias Outcome = AutoScrollPlan.Outcome
    #expect(Outcome.summarizing([.appended(shift: 30), .unchanged, .appended(shift: 12)], body: 900) == .moved(pixels: 42, body: 900))
    #expect(Outcome.summarizing([.lost, .appended(shift: 5)], body: 900) == .moved(pixels: 5, body: 900))
    #expect(Outcome.summarizing([.unchanged, .lost], body: 900) == .lost)
    #expect(Outcome.summarizing([.backward(shift: -40)], body: 900) == .backward)
    #expect(Outcome.summarizing([], body: 900) == .unchanged)
    #expect(Outcome.summarizing([.appended(shift: 30), .full], body: 900) == .full)
}
