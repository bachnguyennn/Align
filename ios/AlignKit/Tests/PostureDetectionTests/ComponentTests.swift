import Foundation
import XCTest
import AlignCore
@testable import PostureDetection

final class MotionFilterTests: XCTestCase {
    func testFirstSamplePassesThroughAndStepReaches63PercentAtTau() {
        var filter = MotionFilter()
        let g0 = Pose.gravity(forward: 0)
        let g1 = Pose.gravity(forward: 10)
        XCTAssertEqual(filter.update(gravity: g0, timestamp: 0, timeConstant: 0.5), g0)
        var out = g0
        for i in 1...500 {
            out = filter.update(gravity: g1, timestamp: Double(i) * 0.001, timeConstant: 0.5)
        }
        let angle = TiltEstimator.angleDegrees(between: g0, and: out)
        XCTAssertEqual(angle, 10 * (1 - exp(-1)), accuracy: 0.05)
    }

    func testResponseIsSampleRateIndependent() {
        let g0 = Pose.gravity(forward: 0)
        let g1 = Pose.gravity(forward: 10)
        var results: [Double] = []
        for rate in [25.0, 100.0] {
            var filter = MotionFilter()
            filter.update(gravity: g0, timestamp: 0, timeConstant: 0.5)
            var out = g0
            for i in 1...Int(rate) {
                out = filter.update(gravity: g1, timestamp: Double(i) / rate, timeConstant: 0.5)
            }
            results.append(TiltEstimator.angleDegrees(between: g0, and: out))
        }
        XCTAssertEqual(results[0], results[1], accuracy: 0.02)
    }

    func testZeroTimeConstantAndReset() {
        var filter = MotionFilter()
        filter.update(gravity: Pose.gravity(forward: 0), timestamp: 0, timeConstant: 0)
        let g1 = Pose.gravity(forward: 12)
        let out = filter.update(gravity: g1, timestamp: 0.04, timeConstant: 0)
        XCTAssertEqual(out.x, g1.x, accuracy: 1e-12)
        XCTAssertEqual(out.y, g1.y, accuracy: 1e-12)
        XCTAssertEqual(out.z, g1.z, accuracy: 1e-12)
        filter.reset()
        XCTAssertNil(filter.value)
    }
}

final class CalibrationServiceTests: XCTestCase {
    private let config = PostureConfiguration.default

    private func run(_ gravities: [Vector3], rate: Double = 25) -> (step: CalibrationService.Step?, used: Int) {
        var service = CalibrationService()
        service.begin()
        var last: CalibrationService.Step?
        for (i, g) in gravities.enumerated() {
            let step = service.add(gravity: g, timestamp: Double(i) / rate, configuration: config)
            last = step
            if case .inProgress = step {
                continue
            }
            return (step, i + 1)
        }
        return (last, gravities.count)
    }

    func testSucceedsWithMeanGravityAfterDuration() {
        let gs = (0..<400).map { i in Pose.gravity(forward: 2 * sin(Double(i) * 0.3), lateral: 1) }
        let result = run(gs)
        XCTAssertEqual(result.used, 251)
        guard case let .succeeded(mean, count)? = result.step else {
            return XCTFail("expected success, got \(String(describing: result.step))")
        }
        XCTAssertEqual(count, 251)
        XCTAssertLessThan(TiltEstimator.angleDegrees(between: mean, and: Pose.gravity(forward: 0, lateral: 1)), 0.2)
    }

    func testReportsProgress() {
        var service = CalibrationService()
        service.begin()
        _ = service.add(gravity: Pose.gravity(forward: 0), timestamp: 0, configuration: config)
        let step = service.add(gravity: Pose.gravity(forward: 0), timestamp: 5, configuration: config)
        XCTAssertEqual(step, .inProgress(progress: 0.5))
    }

    func testFailsWithTooMuchMovement() {
        let gs = (0..<400).map { i in Pose.gravity(forward: 8 * sin(Double(i) * 0.1)) }
        let result = run(gs)
        guard case let .failed(failure, _)? = result.step else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(failure, .tooMuchMovement)
    }

    func testFailsWithInsufficientSamples() {
        let gs = Array(repeating: Pose.gravity(forward: 0), count: 100)
        let result = run(gs, rate: 5)
        XCTAssertEqual(result.used, 51)
        guard case let .failed(failure, _)? = result.step else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(failure, .insufficientSamples)
    }
}

final class PostureDetectorTests: XCTestCase {
    private let config = PostureConfiguration.default

    func testNeutralDeviatingSustainedAndEpisode() {
        var d = PostureDetector()
        XCTAssertEqual(d.update(tilt(0, forward: 10), configuration: config).state, .neutral)
        var out = d.update(tilt(1, forward: 16), configuration: config)
        XCTAssertEqual(out.state, .deviating(direction: .forward, since: 1))
        out = d.update(tilt(30.9, forward: 16), configuration: config)
        XCTAssertEqual(out.state, .deviating(direction: .forward, since: 1))
        out = d.update(tilt(31, forward: 20), configuration: config)
        XCTAssertEqual(out.state, .sustainedTilt(direction: .forward, since: 1))
        XCTAssertTrue(out.becameSustained)
        out = d.update(tilt(32, forward: 13), configuration: config)  // hysteresis: 13 >= 15 - 3
        XCTAssertFalse(out.becameSustained)
        XCTAssertEqual(out.state, .sustainedTilt(direction: .forward, since: 1))
        out = d.update(tilt(40, forward: 11.9), configuration: config)
        XCTAssertEqual(out.state, .neutral)
        XCTAssertEqual(
            out.completedEpisode,
            PostureEpisode(direction: .forward, startTimestamp: 1, endTimestamp: 40, peakDeviationDegrees: 20, reminderTriggered: false)
        )
    }

    func testShortDeviationProducesNoEpisode() {
        var d = PostureDetector()
        _ = d.update(tilt(0, forward: 20), configuration: config)
        let out = d.update(tilt(5, forward: 0), configuration: config)
        XCTAssertEqual(out.state, .neutral)
        XCTAssertNil(out.completedEpisode)
    }

    func testDirectionPrecedenceByRatio() {
        let cases: [(Double, Double, TiltDirection?)] = [
            (16, 0, .forward), (-21, 0, .backward), (0, 15, .right), (0, -15.5, .left),
            (-21, 16, .right),   // backward 21/20 = 1.05 < right 16/15 = 1.067
            (18, -16, .forward), // 1.2 vs 1.067
            (-19, 0, nil), (14.9, 14.9, nil),
        ]
        for (forward, lateral, expected) in cases {
            let got = PostureDetector.dominantDirection(tilt(0, forward: forward, lateral: lateral), configuration: config)
            XCTAssertEqual(got, expected, "for forward \(forward), lateral \(lateral)")
        }
    }

    func testDirectionIsLockedAndReleaseCanStartNewDirection() {
        var d = PostureDetector()
        _ = d.update(tilt(0, forward: 16), configuration: config)
        var out = d.update(tilt(1, forward: 16, lateral: 30), configuration: config)
        XCTAssertEqual(out.state.direction, .forward)
        out = d.update(tilt(2, forward: 5, lateral: 30), configuration: config)
        XCTAssertEqual(out.state, .deviating(direction: .right, since: 2))
    }

    func testInterruptClosesOnlySustained() {
        var d = PostureDetector()
        _ = d.update(tilt(0, forward: 20), configuration: config)
        XCTAssertNil(d.interrupt(at: 3))
        _ = d.update(tilt(10, forward: 20), configuration: config)
        _ = d.update(tilt(40, forward: 20), configuration: config)
        let episode = d.interrupt(at: 41)
        XCTAssertEqual(episode?.startTimestamp, 10)
        XCTAssertEqual(episode?.endTimestamp, 41)
        XCTAssertEqual(d.state, .neutral)
    }

    func testFloatingPointDurationEdgeCountsAsElapsed() {
        var d = PostureDetector()
        XCTAssertLessThan(32.05 - 2.05, 30)  // 29.999999999999996 in IEEE doubles
        _ = d.update(tilt(2.05, forward: 20), configuration: config)
        let out = d.update(tilt(32.05, forward: 20), configuration: config)
        XCTAssertTrue(out.becameSustained)
    }
}

final class ReminderDecisionEngineTests: XCTestCase {
    func testCooldownAndReset() {
        var engine = ReminderDecisionEngine()
        func eval(_ t: TimeInterval) -> ReminderDecision? {
            engine.evaluate(timestamp: t, direction: .forward, deviationDegrees: 20, sustainedSeconds: 30, cooldown: 300)
        }
        XCTAssertNotNil(eval(100))
        XCTAssertNil(eval(399.9))
        XCTAssertNotNil(eval(400))
        XCTAssertNil(eval(401))
        engine.reset()
        XCTAssertNotNil(eval(402))
    }

    func testAllowedWhenClockGoesBackwards() {
        var engine = ReminderDecisionEngine()
        _ = engine.evaluate(timestamp: 1000, direction: .forward, deviationDegrees: 20, sustainedSeconds: 30, cooldown: 300)
        let decision = engine.evaluate(timestamp: 10, direction: .left, deviationDegrees: 20, sustainedSeconds: 30, cooldown: 300)
        XCTAssertEqual(decision, ReminderDecision(timestamp: 10, direction: .left, deviationDegrees: 20, sustainedSeconds: 30))
    }
}
