import XCTest
import AlignCore
@testable import PostureDetection

/// D-022: the "get ready" countdown before a neutral calibration. Mirrors
/// `CalibrationCountdownTest` in `analytics/align-tools` and `pipeline.test.js`.
final class CalibrationCountdownTests: XCTestCase {
    private let config = PostureConfiguration.default

    /// Looking down at the phone (30°) before `lookUpAt`, neutral afterwards.
    private func lookUp(_ t: Double, at lookUpAt: Double) -> Vector3 {
        Pose.gravity(forward: t < lookUpAt ? 30 : 0)
    }

    private func sample(_ t: Double, forward: Double) -> MotionSample {
        let q = Pose.attitude(forward: forward, lateral: 0)
        return MotionSample(timestamp: t, attitude: q, gravity: Pose.gravity(q))
    }

    func testDefaultCountdownIsThreeSecondsAndDecodes() throws {
        XCTAssertEqual(config.calibrationCountdown, 3)
        let decoded = try JSONDecoder().decode(PostureConfiguration.self, from: Data(#"{"calibrationCountdown": 0}"#.utf8))
        XCTAssertEqual(decoded.calibrationCountdown, 0)
        // A configuration stored before D-022 has no countdown key: it gets the default.
        let old = try JSONDecoder().decode(PostureConfiguration.self, from: Data(#"{"calibrationDuration": 10}"#.utf8))
        XCTAssertEqual(old.calibrationCountdown, 3)
    }

    func testCountdownSamplesAreDiscardedAndTheHoldStartsAfterIt() {
        var service = CalibrationService()
        service.begin()
        XCTAssertTrue(service.isCountingDown)
        XCTAssertEqual(service.countdownRemaining(countdown: 3), 3)  // before the first sample
        var last: CalibrationService.Step?
        var i = 0
        while i <= 13 * 25 {
            let t = Double(i) / 25
            let step = service.add(gravity: lookUp(t, at: 2), timestamp: t, configuration: config)
            last = step
            if t < 3 - 1e-9 {
                XCTAssertEqual(step, .inProgress(progress: 0))
                XCTAssertTrue(service.isCountingDown)
                XCTAssertEqual(service.countdownRemaining(countdown: 3), 3 - t, accuracy: 1e-9)
            } else {
                XCTAssertFalse(service.isCountingDown, "hold started at t = \(t)")
                XCTAssertEqual(service.countdownRemaining(countdown: 3), 0)
            }
            if case .inProgress = step {
                i += 1
                continue
            }
            break
        }
        XCTAssertEqual(Double(i) / 25, 13, accuracy: 1e-9)  // 3 s countdown + 10 s hold
        guard case .succeeded(let mean, let count)? = last else {
            return XCTFail("expected success, got \(String(describing: last))")
        }
        XCTAssertEqual(count, 251)  // t = 3.0 ... 13.0 inclusive; the 75 countdown samples are dropped
        XCTAssertEqual(TiltEstimator.angleDegrees(between: mean, and: Pose.gravity(forward: 0)), 0, accuracy: 1e-9)
    }

    func testWithoutTheCountdownLookingUpFailsTheCalibration() {
        var service = CalibrationService()
        service.begin()
        var last: CalibrationService.Step?
        for i in 0...(10 * 25) {
            let t = Double(i) / 25
            last = service.add(gravity: lookUp(t, at: 2), timestamp: t, configuration: .noCountdown)
        }
        guard case .failed(let reason, _)? = last else {
            return XCTFail("expected failure, got \(String(describing: last))")
        }
        XCTAssertEqual(reason, .tooMuchMovement)
    }

    func testMovementDuringTheHoldStillFails() {
        var service = CalibrationService()
        service.begin()
        var last: CalibrationService.Step?
        for i in 0...(13 * 25) {
            let t = Double(i) / 25
            // Neutral during the countdown, then a 9° nod for the first half of the hold.
            last = service.add(gravity: Pose.gravity(forward: t >= 3 && t < 8 ? 9 : 0), timestamp: t, configuration: config)
        }
        guard case .failed(let reason, _)? = last else {
            return XCTFail("expected failure, got \(String(describing: last))")
        }
        XCTAssertEqual(reason, .tooMuchMovement)
    }

    func testMonitorReportsCalibratingAtZeroAndTheRemainingCountdown() {
        let monitor = PostureMonitor(configuration: config)
        _ = monitor.process(sample(0, forward: 30))
        XCTAssertNil(monitor.calibrationCountdownRemaining)  // not calibrating
        monitor.beginCalibration()
        XCTAssertEqual(monitor.calibrationCountdownRemaining, 3)
        var update = monitor.process(sample(0.04, forward: 30))
        XCTAssertEqual(update.state, .calibrating(progress: 0))
        XCTAssertEqual(monitor.calibrationCountdownRemaining ?? -1, 3, accuracy: 1e-9)  // starts on this sample
        for i in 2...50 {
            update = monitor.process(sample(Double(i) * 0.04, forward: 30))
        }
        XCTAssertEqual(update.state, .calibrating(progress: 0))
        XCTAssertEqual(monitor.calibrationCountdownRemaining ?? -1, 3 - (2 - 0.04), accuracy: 1e-9)
        for i in 51...100 {
            update = monitor.process(sample(Double(i) * 0.04, forward: 0))
        }
        XCTAssertNil(monitor.calibrationCountdownRemaining)  // hold started at t = 3.04
        guard case .calibrating(let progress) = update.state else {
            return XCTFail("expected calibrating, got \(update.state)")
        }
        XCTAssertGreaterThan(progress, 0)
    }

    func testCancelDuringTheCountdownStopsWithoutAnOutcome() {
        let monitor = PostureMonitor(configuration: config)
        monitor.beginCalibration()
        for i in 0..<25 {
            XCTAssertNil(monitor.process(sample(Double(i) * 0.04, forward: 30)).calibrationOutcome)
        }
        monitor.cancelCalibration()
        XCTAssertNil(monitor.calibrationCountdownRemaining)
        let update = monitor.process(sample(1, forward: 0))
        XCTAssertEqual(update.state, .needsCalibration)
        XCTAssertNil(update.calibrationOutcome)
    }
}
