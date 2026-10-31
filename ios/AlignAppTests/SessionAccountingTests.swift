import XCTest
import AlignCore
@testable import Align

final class SessionAccumulatorTests: XCTestCase {
    private let maxStep: TimeInterval = 1.0

    func testFirstSampleAddsNoTime() {
        var accumulator = SessionAccumulator()
        accumulator.record(state: .neutral, at: 100, maxStep: maxStep)
        XCTAssertEqual(accumulator.monitoredSeconds, 0)
        XCTAssertNil(accumulator.withinThresholdFraction)
    }

    func testNeutralAndDeviatingCountAsWithinThreshold() {
        var accumulator = SessionAccumulator()
        accumulator.record(state: .neutral, at: 0, maxStep: maxStep)
        accumulator.record(state: .deviating(direction: .forward, since: 0.5), at: 0.5, maxStep: maxStep)
        accumulator.record(state: .deviating(direction: .forward, since: 0.5), at: 1.0, maxStep: maxStep)
        XCTAssertEqual(accumulator.withinThresholdSeconds, 1.0, accuracy: 1e-9)
        XCTAssertEqual(accumulator.monitoredSeconds, 1.0, accuracy: 1e-9)
        XCTAssertEqual(accumulator.sustainedDeviationSeconds, 0)
    }

    func testIntervalIsAttributedToPreviousState() {
        var accumulator = SessionAccumulator()
        accumulator.record(state: .neutral, at: 0, maxStep: maxStep)
        // The 0.4 s before this update were spent neutral, even though the new state is sustained.
        accumulator.record(state: .sustainedTilt(direction: .forward, since: -30), at: 0.4, maxStep: maxStep)
        accumulator.record(state: .sustainedTilt(direction: .forward, since: -30), at: 1.0, maxStep: maxStep)
        XCTAssertEqual(accumulator.withinThresholdSeconds, 0.4, accuracy: 1e-9)
        XCTAssertEqual(accumulator.sustainedDeviationSeconds, 0.6, accuracy: 1e-9)
        XCTAssertEqual(accumulator.monitoredSeconds, 1.0, accuracy: 1e-9)
        XCTAssertEqual(accumulator.withinThresholdFraction ?? -1, 0.4, accuracy: 1e-9)
    }

    func testUncalibratedStatesAreNotMonitored() {
        var accumulator = SessionAccumulator()
        accumulator.record(state: .unavailable, at: 0, maxStep: maxStep)
        accumulator.record(state: .needsCalibration, at: 0.5, maxStep: maxStep)
        accumulator.record(state: .calibrating(progress: 0.2), at: 1.0, maxStep: maxStep)
        accumulator.record(state: .neutral, at: 1.5, maxStep: maxStep)
        XCTAssertEqual(accumulator.monitoredSeconds, 0)
        accumulator.record(state: .neutral, at: 2.0, maxStep: maxStep)
        XCTAssertEqual(accumulator.monitoredSeconds, 0.5, accuracy: 1e-9)
    }

    func testStepIsCappedAtMaxSampleGap() {
        var accumulator = SessionAccumulator()
        accumulator.record(state: .neutral, at: 0, maxStep: maxStep)
        accumulator.record(state: .neutral, at: 10, maxStep: maxStep)
        XCTAssertEqual(accumulator.monitoredSeconds, 1.0, accuracy: 1e-9)
    }

    func testBreakContinuityDropsTheGap() {
        var accumulator = SessionAccumulator()
        accumulator.record(state: .neutral, at: 0, maxStep: maxStep)
        accumulator.record(state: .neutral, at: 0.5, maxStep: maxStep)
        accumulator.breakContinuity()
        accumulator.record(state: .neutral, at: 0.9, maxStep: maxStep)
        accumulator.record(state: .neutral, at: 1.2, maxStep: maxStep)
        XCTAssertEqual(accumulator.monitoredSeconds, 0.8, accuracy: 1e-9)
    }

    func testOutOfOrderSampleIsIgnored() {
        var accumulator = SessionAccumulator()
        accumulator.record(state: .neutral, at: 1.0, maxStep: maxStep)
        accumulator.record(state: .sustainedTilt(direction: .left, since: 0), at: 0.5, maxStep: maxStep)
        accumulator.record(state: .neutral, at: 1.5, maxStep: maxStep)
        // Interval 1.0 → 1.5 belongs to the neutral state recorded at 1.0.
        XCTAssertEqual(accumulator.withinThresholdSeconds, 0.5, accuracy: 1e-9)
        XCTAssertEqual(accumulator.sustainedDeviationSeconds, 0)
    }

    func testRealisticStreamAt25Hz() {
        var accumulator = SessionAccumulator()
        let dt = 1.0 / 25.0
        // 10 s neutral, then 30 s sustained tilt, then 5 s neutral.
        var t = 0.0
        for _ in 0..<250 {
            accumulator.record(state: .neutral, at: t, maxStep: maxStep)
            t += dt
        }
        for _ in 0..<750 {
            accumulator.record(state: .sustainedTilt(direction: .forward, since: 0), at: t, maxStep: maxStep)
            t += dt
        }
        for _ in 0..<125 {
            accumulator.record(state: .neutral, at: t, maxStep: maxStep)
            t += dt
        }
        XCTAssertEqual(accumulator.monitoredSeconds, 1124 * dt, accuracy: 1e-6)
        XCTAssertEqual(accumulator.sustainedDeviationSeconds, 750 * dt, accuracy: 1e-6)
        XCTAssertEqual(accumulator.withinThresholdSeconds, 374 * dt, accuracy: 1e-6)
    }

    func testReminderCount() {
        var accumulator = SessionAccumulator()
        accumulator.recordReminder()
        accumulator.recordReminder()
        XCTAssertEqual(accumulator.reminderCount, 2)
    }
}

final class MonotonicClockTests: XCTestCase {
    func testConvertsUptimeToDate() {
        let reference = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = MonotonicClock(referenceUptime: 5_000, referenceDate: reference)
        XCTAssertEqual(clock.date(forUptime: 5_000), reference)
        XCTAssertEqual(clock.date(forUptime: 4_970).timeIntervalSince(reference), -30, accuracy: 1e-9)
        XCTAssertEqual(clock.date(forUptime: 5_012.5).timeIntervalSince(reference), 12.5, accuracy: 1e-9)
    }

    func testNowMatchesArchitectureFormula() {
        let clock = MonotonicClock.now()
        let timestamp = clock.referenceUptime - 42
        // architecture.md: Date(timeIntervalSinceNow: timestamp - ProcessInfo.processInfo.systemUptime)
        let expected = Date(timeIntervalSinceNow: timestamp - ProcessInfo.processInfo.systemUptime)
        XCTAssertEqual(clock.date(forUptime: timestamp).timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.5)
    }
}

final class DailySummaryTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    func testReturnsOneSummaryPerDayOldestFirstIncludingEmptyDays() {
        let summaries = DailySummaryBuilder.summaries(from: [], days: 7, endingOn: date(31, 15), calendar: calendar)
        XCTAssertEqual(summaries.count, 7)
        XCTAssertEqual(summaries.first?.date, date(25, 0))
        XCTAssertEqual(summaries.last?.date, date(31, 0))
        XCTAssertTrue(summaries.allSatisfy { $0.totalMonitoredMinutes == 0 && $0.reminderCount == 0 })
    }

    func testAggregatesSessionsByStartDay() {
        let records = [
            SessionRecord(startedAt: date(31, 9), monitoredSeconds: 1200, withinThresholdSeconds: 900, sustainedDeviationSeconds: 300, reminderCount: 1),
            SessionRecord(startedAt: date(31, 14), monitoredSeconds: 600, withinThresholdSeconds: 600, sustainedDeviationSeconds: 0, reminderCount: 0),
            SessionRecord(startedAt: date(29, 23, 50), monitoredSeconds: 1800, withinThresholdSeconds: 1500, sustainedDeviationSeconds: 300, reminderCount: 2),
        ]
        let summaries = DailySummaryBuilder.summaries(from: records, days: 7, endingOn: date(31, 18), calendar: calendar)
        let today = summaries.last!
        XCTAssertEqual(today.totalMonitoredMinutes, 30, accuracy: 1e-9)
        XCTAssertEqual(today.withinThresholdMinutes, 25, accuracy: 1e-9)
        XCTAssertEqual(today.sustainedDeviationMinutes, 5, accuracy: 1e-9)
        XCTAssertEqual(today.reminderCount, 1)

        // A session that started before midnight counts for its start day (v1 rule).
        let oct29 = summaries.first { $0.date == date(29, 0) }!
        XCTAssertEqual(oct29.totalMonitoredMinutes, 30, accuracy: 1e-9)
        XCTAssertEqual(oct29.reminderCount, 2)
        let oct30 = summaries.first { $0.date == date(30, 0) }!
        XCTAssertEqual(oct30.totalMonitoredMinutes, 0)
    }

    func testIgnoresSessionsOutsideTheWindow() {
        let records = [
            SessionRecord(startedAt: date(20, 10), monitoredSeconds: 600, withinThresholdSeconds: 600, sustainedDeviationSeconds: 0, reminderCount: 3),
        ]
        let summaries = DailySummaryBuilder.summaries(from: records, days: 7, endingOn: date(31, 10), calendar: calendar)
        XCTAssertEqual(summaries.reduce(0) { $0 + $1.reminderCount }, 0)
    }

    func testZeroDaysReturnsEmpty() {
        XCTAssertTrue(DailySummaryBuilder.summaries(from: [], days: 0, endingOn: date(31, 10), calendar: calendar).isEmpty)
    }
}
