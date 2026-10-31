import Foundation
import XCTest
import AlignCore
@testable import PostureDetection

/// Mirrors analytics/experiments/tests/test_monitor.py.
final class PostureMonitorTests: XCTestCase {
    private let dt = 1.0 / 25.0
    /// A 0 → 25° step through the τ = 0.5 s filter crosses 15° after τ·ln(25/10).
    private let stepLag = 0.5 * log(25.0 / 10.0)

    private func storedBaseline(version: Int = 1) -> NeutralBaseline {
        NeutralBaseline(gravity: Vector3(x: 0, y: 0, z: -1), capturedAt: Date(), sampleCount: 250, version: version)
    }

    private func calibratedMonitor(_ configuration: PostureConfiguration = .default) -> PostureMonitor {
        let monitor = PostureMonitor(configuration: configuration)
        monitor.beginCalibration()
        feed(monitor, from: 0, to: 10 + dt)
        XCTAssertNotNil(monitor.baseline)
        return monitor
    }

    func testInitialStates() {
        let monitor = PostureMonitor()
        XCTAssertEqual(monitor.state, .unavailable)
        let update = monitor.process(Pose.sample(0))
        XCTAssertEqual(update.state, .needsCalibration)
        XCTAssertNil(update.tilt)
        let withBaseline = PostureMonitor(baseline: storedBaseline())
        XCTAssertEqual(withBaseline.process(Pose.sample(0)).state, .neutral)
    }

    func testCalibrationProgressSingleOutcomeAndVersion() {
        let monitor = PostureMonitor()
        monitor.beginCalibration()
        XCTAssertEqual(monitor.state, .calibrating(progress: 0))
        let updates = feed(monitor, from: 0, to: 12)
        let outcomes = updates.filter { $0.calibrationOutcome != nil }
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes.first?.timestamp ?? -1, 10, accuracy: 1e-9)
        XCTAssertEqual(outcomes.first?.calibrationOutcome?.name, "succeeded")
        XCTAssertEqual(outcomes.first?.state, .neutral)
        XCTAssertEqual(updates[125].state.progress ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(monitor.baseline?.version, 1)
        XCTAssertEqual(monitor.baseline?.sampleCount, 251)
        monitor.beginCalibration()
        feed(monitor, from: 12, to: 23)
        XCTAssertEqual(monitor.baseline?.version, 2)
    }

    func testVersionContinuesFromStoredBaseline() {
        let monitor = PostureMonitor(baseline: storedBaseline(version: 5))
        monitor.beginCalibration()
        feed(monitor, from: 0, to: 10.5)
        XCTAssertEqual(monitor.baseline?.version, 6)
    }

    func testSustainedForwardTiltRemindsOnceAndClosesEpisode() {
        let monitor = calibratedMonitor()
        var updates = feed(monitor, from: 10.04, to: 20)
        updates += feed(monitor, from: 20, to: 80, forward: 25)
        updates += feed(monitor, from: 80, to: 85)
        let reminders = updates.compactMap { $0.reminder }
        XCTAssertEqual(reminders.count, 1)
        guard let reminder = reminders.first else { return }
        XCTAssertEqual(reminder.direction, .forward)
        XCTAssertEqual(reminder.sustainedSeconds, 30, accuracy: 0.05)
        XCTAssertEqual(reminder.timestamp, 50 + stepLag, accuracy: dt)
        XCTAssertEqual(reminder.deviationDegrees, 25, accuracy: 0.1)
        let episodes = updates.compactMap { $0.completedEpisode }
        XCTAssertEqual(episodes.count, 1)
        XCTAssertEqual(episodes.first?.reminderTriggered, true)
        XCTAssertEqual(episodes.first?.endTimestamp ?? -1, 80, accuracy: 0.5)
        XCTAssertEqual(monitor.state, .neutral)
    }

    func testStateSinceIsDeviationOnset() {
        let monitor = calibratedMonitor()
        feed(monitor, from: 10.04, to: 12)
        feed(monitor, from: 12, to: 50, forward: 25)
        XCTAssertEqual(monitor.state.kindName, "sustainedTilt")
        XCTAssertEqual(monitor.state.since ?? -1, 12 + stepLag, accuracy: dt)
    }

    func testTiltIsReportedWithBaselineAndLateralDirection() {
        let monitor = calibratedMonitor()
        let updates = feed(monitor, from: 10.04, to: 15, lateral: -20)
        XCTAssertEqual(updates.last?.tilt?.lateralDegrees ?? 0, -20, accuracy: 0.1)
        XCTAssertEqual(updates.last?.state.direction, .left)
    }

    func testCooldownBlocksSecondEpisodeAndResetCooldownAllowsIt() {
        let monitor = calibratedMonitor()
        feed(monitor, from: 10.04, to: 12)
        let first = feed(monitor, from: 12, to: 50, forward: 25)
        feed(monitor, from: 50, to: 55)
        let second = feed(monitor, from: 55, to: 90, forward: 25)
        XCTAssertEqual(first.filter { $0.reminder != nil }.count, 1)
        XCTAssertEqual(second.filter { $0.reminder != nil }.count, 0)
        feed(monitor, from: 90, to: 95)
        monitor.resetCooldown()
        let third = feed(monitor, from: 95, to: 130, forward: 25)
        XCTAssertEqual(third.filter { $0.reminder != nil }.count, 1)
    }

    func testInterruptClosesEpisodeAndResets() {
        let monitor = calibratedMonitor()
        feed(monitor, from: 10.04, to: 12)
        feed(monitor, from: 12, to: 45, forward: 25)
        let update = monitor.interrupt(at: 45.5)
        XCTAssertEqual(update.completedEpisode?.endTimestamp, 45.5)
        XCTAssertEqual(update.state, .unavailable)
        XCTAssertNil(update.tilt)
        let next = monitor.process(Pose.sample(50, forward: 25))
        XCTAssertEqual(next.state, .deviating(direction: .forward, since: 50))
    }

    func testInterruptFailsCalibration() {
        let monitor = PostureMonitor()
        monitor.beginCalibration()
        feed(monitor, from: 0, to: 5)
        let update = monitor.interrupt(at: 5)
        XCTAssertEqual(update.calibrationOutcome, .failed(.sensorInterrupted))
        XCTAssertEqual(monitor.state, .unavailable)
        XCTAssertEqual(monitor.process(Pose.sample(6)).state, .needsCalibration)
    }

    func testGapActsLikeInterruptAtPreviousTimestamp() {
        let monitor = calibratedMonitor()
        feed(monitor, from: 10.04, to: 12)
        feed(monitor, from: 12, to: 45, forward: 25)
        let last = monitor.lastProcessedTimestamp ?? -1
        XCTAssertEqual(last, 45 - dt, accuracy: 1e-6)
        let update = monitor.process(Pose.sample(47, forward: 25))
        XCTAssertEqual(update.completedEpisode?.endTimestamp, last)
        XCTAssertEqual(update.state, .deviating(direction: .forward, since: 47))
    }

    func testGapDuringCalibrationReportsSensorInterruptedOnNextSample() {
        let monitor = PostureMonitor()
        monitor.beginCalibration()
        feed(monitor, from: 0, to: 4)
        let update = monitor.process(Pose.sample(6))
        XCTAssertEqual(update.calibrationOutcome, .failed(.sensorInterrupted))
        XCTAssertEqual(update.state, .needsCalibration)
    }

    func testDecimationCapsProcessingRate() {
        var configuration = PostureConfiguration.default
        configuration.maxProcessingRateHz = 10
        let monitor = PostureMonitor(configuration: configuration, baseline: storedBaseline())
        var processed = 0
        for i in 0..<250 {
            let before = monitor.lastProcessedTimestamp
            _ = monitor.process(Pose.sample((Double(i) * dt * 1e6).rounded() / 1e6))
            if monitor.lastProcessedTimestamp != before {
                processed += 1
            }
        }
        XCTAssertEqual(Double(processed), 100, accuracy: 1)
    }

    func testConfigurationChangeAppliesFromNextSample() {
        let monitor = calibratedMonitor()
        feed(monitor, from: 10.04, to: 12)
        feed(monitor, from: 12, to: 14, forward: 12)
        XCTAssertEqual(monitor.state, .neutral)
        monitor.configuration.forwardThresholdDegrees = 10
        let update = monitor.process(Pose.sample(14, forward: 12))
        XCTAssertEqual(update.state.kindName, "deviating")
    }

    func testMissingGravityIsDerivedFromAttitude() {
        let monitor = PostureMonitor(baseline: storedBaseline())
        _ = monitor.process(Pose.sample(0))
        var update: PostureUpdate?
        for i in 1..<100 {
            update = monitor.process(Pose.sample(Double(i) * dt, forward: 20, includeGravity: false))
        }
        XCTAssertEqual(update?.tilt?.forwardDegrees ?? 0, 20, accuracy: 0.01)
    }

    func testNonIncreasingAndZeroGravitySamplesAreIgnored() {
        let monitor = PostureMonitor(baseline: storedBaseline())
        _ = monitor.process(Pose.sample(1))
        let before = monitor.lastProcessedTimestamp
        _ = monitor.process(Pose.sample(1, forward: 30))
        _ = monitor.process(Pose.sample(0.5, forward: 30))
        _ = monitor.process(MotionSample(timestamp: 2, attitude: .identity, gravity: .zero))
        XCTAssertEqual(monitor.lastProcessedTimestamp, before)
    }

    func testBeginCalibrationDuringSustainedTiltDeliversEpisodeOnNextUpdate() {
        let monitor = calibratedMonitor()
        feed(monitor, from: 10.04, to: 12)
        feed(monitor, from: 12, to: 45, forward: 25)
        let last = monitor.lastProcessedTimestamp
        monitor.beginCalibration()
        XCTAssertEqual(monitor.state.kindName, "calibrating")
        let update = monitor.process(Pose.sample(45))
        XCTAssertEqual(update.completedEpisode?.endTimestamp, last)
    }

    func testCancelCalibrationKeepsPreviousBaseline() {
        let monitor = calibratedMonitor()
        let baseline = monitor.baseline
        monitor.beginCalibration()
        feed(monitor, from: 10.04, to: 13)
        monitor.cancelCalibration()
        let update = monitor.process(Pose.sample(13))
        XCTAssertEqual(monitor.baseline, baseline)
        XCTAssertEqual(update.state, .neutral)
        XCTAssertNil(update.calibrationOutcome)
    }
}
