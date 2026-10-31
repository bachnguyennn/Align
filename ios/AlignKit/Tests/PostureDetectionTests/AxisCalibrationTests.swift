import Foundation
import XCTest
import AlignCore
@testable import PostureDetection

/// Guided-nod axis calibration (D-017). Mirrors `AxisCalibrationTest` in `analytics/align-tools`.
final class AxisCalibrationTests: XCTestCase {
    private let rate = 25.0
    private let dt = 1.0 / 25.0
    private let rad = Double.pi / 180
    private let down = Vector3(x: 0, y: 0, z: -1)

    private struct Mount {
        var pitch: Double
        var roll: Double
        var yaw: Double
        static let level = Mount(pitch: 0, roll: 0, yaw: 0)

        func sample(_ t: TimeInterval, forward: Double, lateral: Double, heading: Double) -> MotionSample {
            Pose.mountedSample(t, forward: forward, lateral: lateral, heading: heading,
                               mountPitch: pitch, mountRoll: roll, mountYaw: yaw)
        }
    }

    /// Nod profile: 1 s down to `depth`, 1 s back, then neutral (relative seconds).
    private func nod(_ rel: Double, _ depth: Double) -> Double {
        if rel < 0 {
            return 0
        }
        if rel < 1 {
            return depth * rel
        }
        if rel < 2 {
            return depth * (2 - rel)
        }
        return 0
    }

    /// Feeds samples for start <= t < end following `profile(rel) -> (forward, lateral)`.
    @discardableResult
    private func feed(
        _ monitor: PostureMonitor,
        _ mount: Mount,
        from start: TimeInterval,
        to end: TimeInterval,
        _ profile: (Double) -> (Double, Double)
    ) -> [PostureUpdate] {
        var updates: [PostureUpdate] = []
        var i = 0
        while true {
            let t = ((start + Double(i) / rate) * 1e6).rounded() / 1e6
            if t >= end - 1e-9 {
                break
            }
            let pose = profile(t - start)
            updates.append(monitor.process(mount.sample(t, forward: pose.0, lateral: pose.1, heading: 17 * Double(i) / rate)))
            i += 1
        }
        return updates
    }

    @discardableResult
    private func hold(
        _ monitor: PostureMonitor,
        _ mount: Mount,
        from start: TimeInterval,
        to end: TimeInterval,
        forward: Double = 0,
        lateral: Double = 0
    ) -> [PostureUpdate] {
        feed(monitor, mount, from: start, to: end) { _ in (forward, lateral) }
    }

    /// Neutral-calibrated monitor (0 <= t <= 10 s); the next sample is at t = 10.04.
    private func calibrated(_ mount: Mount, _ configuration: PostureConfiguration = .default) -> PostureMonitor {
        let monitor = PostureMonitor(configuration: configuration)
        monitor.beginCalibration()
        hold(monitor, mount, from: 0, to: 10 + dt)
        XCTAssertEqual(monitor.baseline?.version, 1)
        XCTAssertNil(monitor.baseline?.learnedAxes)
        return monitor
    }

    private func axisOutcomes(_ updates: [PostureUpdate]) -> [AxisCalibrationOutcome] {
        updates.compactMap { $0.axisCalibrationOutcome }
    }

    private func yaw(_ monitor: PostureMonitor) -> Double {
        AxisCalibrationService.signedYawDegrees(
            forwardAxis: monitor.effectiveAxes.forwardAxis,
            baselineGravity: monitor.baseline?.gravity ?? down,
            reference: monitor.configuration.axes
        )
    }

    private func assertVector(_ got: Vector3?, _ want: Vector3, accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
        guard let got = got else {
            return XCTFail("nil vector", file: file, line: line)
        }
        XCTAssertEqual(got.x, want.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(got.y, want.y, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(got.z, want.z, accuracy: accuracy, file: file, line: line)
    }

    // MARK: - Fit

    /// For the default axes and baseline gravity (0, 0, −1), lateral = g × forward reproduces (0, 1, 0).
    func testFitReproducesDefaultAxesForANodAboutTheDefaultForwardAxis() {
        let rotations = [4.0, 10, 20, 10, 4, -6].map { HeadAxisConvention.airPodsDefault.forwardAxis * ($0 * rad) }
        let fit = AxisCalibrationService.fit(rotations, baseline: down, reference: .airPodsDefault)
        assertVector(fit.axes?.forwardAxis, Vector3(x: -1, y: 0, z: 0), accuracy: 1e-12)
        assertVector(fit.axes?.lateralAxis, Vector3(x: 0, y: 1, z: 0), accuracy: 1e-12)
        XCTAssertEqual(fit.yawDegrees, 0, accuracy: 1e-9)
        XCTAssertEqual(fit.offAxisRatio, 0, accuracy: 1e-12)
        XCTAssertEqual(fit.samplesUsed, 6)
        XCTAssertEqual(down.cross(HeadAxisConvention.airPodsDefault.forwardAxis), Vector3(x: 0, y: 1, z: 0))
    }

    func testFitSignFollowsDefaultForNodDownOrUpAndMeasuresYaw() {
        let axis = Vector3(x: -cos(30 * rad), y: sin(30 * rad), z: 0)
        for sign in [1.0, -1.0] {
            let rotations = [axis * (sign * 15 * rad), axis * (sign * 25 * rad)]
            let fit = AxisCalibrationService.fit(rotations, baseline: down, reference: .airPodsDefault)
            assertVector(fit.axes?.forwardAxis, axis, accuracy: 1e-12)
            XCTAssertEqual(fit.yawDegrees, 30, accuracy: 1e-9)
            XCTAssertGreaterThan(fit.axes?.forwardAxis.dot(HeadAxisConvention.airPodsDefault.forwardAxis) ?? -1, 0)
        }
    }

    func testLShapedMotionHasALargeOffAxisRatio() {
        let f = HeadAxisConvention.airPodsDefault.forwardAxis
        let l = HeadAxisConvention.airPodsDefault.lateralAxis
        let rotations = [f * (20 * rad), f * (10 * rad), l * (15 * rad), l * (8 * rad)]
        let fit = AxisCalibrationService.fit(rotations, baseline: down, reference: .airPodsDefault)
        XCTAssertGreaterThan(fit.offAxisRatio, 0.35)
    }

    func testFloorAndReturnLevelsAreCappedAtHalfTheMinimumNod() {
        XCTAssertEqual(AxisCalibrationService.floorDegrees(minimumNodDegrees: 12), 3)
        XCTAssertEqual(AxisCalibrationService.returnDegrees(minimumNodDegrees: 12), 5)
        XCTAssertEqual(AxisCalibrationService.floorDegrees(minimumNodDegrees: 4), 2)
        XCTAssertEqual(AxisCalibrationService.returnDegrees(minimumNodDegrees: 4), 2)
    }

    // MARK: - Service

    func testServiceReportsProgressAndFinishesWhenTheHeadReturns() {
        var service = AxisCalibrationService()
        let config = PostureConfiguration.default
        service.begin()
        XCTAssertEqual(service.progress(duration: config.axisCalibrationDuration), 0)
        var finished: AxisCalibrationService.Step?
        var index = 0
        for i in 0..<400 {
            let t = Double(i) / rate
            let g = Pose.gravity(forward: nod(t - 1, 20))
            let step = service.add(gravity: g, timestamp: t, baselineGravity: down, configuration: config)
            if case let .inProgress(progress) = step {
                if i == 25 {
                    XCTAssertEqual(progress, 1.0 / 8.0, accuracy: 1e-9)
                }
                continue
            }
            finished = step
            index = i
            break
        }
        XCTAssertFalse(service.isActive)
        // Back within 5° on the way up: 20 * (2 - rel) <= 5 at rel >= 1.75, i.e. t = 2.76.
        XCTAssertEqual(Double(index) / rate, 2.76, accuracy: dt)
        guard case let .succeeded(axes)? = finished else {
            return XCTFail("expected success, got \(String(describing: finished))")
        }
        assertVector(axes.forwardAxis, Vector3(x: -1, y: 0, z: 0), accuracy: 1e-9)
    }

    func testServiceTimesOutWithoutANod() {
        var service = AxisCalibrationService()
        service.begin()
        var finished: AxisCalibrationService.Step?
        var count = 0
        for i in 0..<400 {
            count = i + 1
            let step = service.add(gravity: Pose.gravity(forward: 2, lateral: 1), timestamp: Double(i) / rate,
                                   baselineGravity: down, configuration: .default)
            if case .inProgress = step {
                continue
            }
            finished = step
            break
        }
        XCTAssertEqual(finished, .failed(.noNodDetected))
        XCTAssertEqual(count, 201)  // t = 0 ... 8.0 inclusive
    }

    // MARK: - Monitor

    func testNeedsBaselineIsReportedOnTheNextUpdateOnly() {
        let monitor = PostureMonitor()
        monitor.beginAxisCalibration()
        XCTAssertEqual(monitor.state, .unavailable)
        let update = monitor.process(Mount.level.sample(0, forward: 0, lateral: 0, heading: 0))
        XCTAssertEqual(update.axisCalibrationOutcome, .failed(.needsBaseline))
        XCTAssertEqual(update.state, .needsCalibration)
        XCTAssertEqual(axisOutcomes(hold(monitor, .level, from: dt, to: 2)).count, 0)

        let viaInterrupt = PostureMonitor()
        viaInterrupt.beginAxisCalibration()
        XCTAssertEqual(viaInterrupt.interrupt(at: 1).axisCalibrationOutcome, .failed(.needsBaseline))
    }

    func testNoNodDetectedAfterTheDurationKeepsDefaultAxes() {
        let monitor = calibrated(.level)
        monitor.beginAxisCalibration()
        let updates = hold(monitor, .level, from: 10.04, to: 20, forward: 1, lateral: 0.5)
        let withOutcome = updates.filter { $0.axisCalibrationOutcome != nil }
        XCTAssertEqual(withOutcome.count, 1)
        XCTAssertEqual(withOutcome.first?.axisCalibrationOutcome, .failed(.noNodDetected))
        XCTAssertEqual(withOutcome.first?.timestamp ?? -1, 18.04, accuracy: 1e-6)
        XCTAssertEqual(monitor.effectiveAxes, .airPodsDefault)
        XCTAssertNil(monitor.baseline?.learnedAxes)
        XCTAssertEqual(monitor.baseline?.version, 1)
        XCTAssertEqual(monitor.state, .neutral)
    }

    func testSidewaysTiltIsRejectedAsInconsistentMotion() {
        let monitor = calibrated(.level)
        monitor.beginAxisCalibration()
        let updates = feed(monitor, .level, from: 10.04, to: 16) { rel in (0, self.nod(rel - 0.5, 20)) }
        XCTAssertEqual(axisOutcomes(updates), [.failed(.inconsistentMotion)])
        XCTAssertEqual(monitor.effectiveAxes, .airPodsDefault)
        XCTAssertEqual(monitor.baseline?.version, 1)
    }

    func testDiagonalMotionBeyondMaxYawIsRejected() {
        let monitor = calibrated(.level)
        monitor.beginAxisCalibration()
        let c = cos(60 * rad)
        let s = sin(60 * rad)
        let updates = feed(monitor, .level, from: 10.04, to: 16) { rel in
            (self.nod(rel - 0.5, 20) * c, self.nod(rel - 0.5, 20) * s)
        }
        XCTAssertEqual(axisOutcomes(updates).first, .failed(.inconsistentMotion))
    }

    /// Noise-free yawed earbud (25°, plus the generator's 8°/−3° pitch/roll): yaw recovered within 1°.
    func testYawedEarbudIsRecoveredAndRemovesCrosstalk() {
        let mount = Mount(pitch: 8, roll: -3, yaw: 25)
        let monitor = calibrated(mount)
        monitor.beginAxisCalibration()
        XCTAssertEqual(monitor.state.kindName, "calibrating")
        let updates = feed(monitor, mount, from: 10.04, to: 16) { rel in (self.nod(rel - 0.5, 20), 0) }
        let outcomes = axisOutcomes(updates)
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes.first?.name, "succeeded")
        XCTAssertEqual(outcomes.first?.axes, monitor.baseline?.learnedAxes)
        XCTAssertEqual(monitor.baseline?.learnedAxes, monitor.effectiveAxes)
        XCTAssertEqual(monitor.baseline?.version, 2)
        let trueYaw = Pose.trueYawDegrees(pitch: 8, roll: -3, yaw: 25)
        XCTAssertEqual(yaw(monitor), trueYaw, accuracy: 1e-6)
        XCTAssertEqual(yaw(monitor), 25, accuracy: 1)

        let held = hold(monitor, mount, from: 16, to: 20, forward: 20)
        let tilt = held.last?.tilt
        XCTAssertEqual(tilt?.forwardDegrees ?? 0, 20, accuracy: 0.02)  // filter residual 20·exp(−4/0.5)
        XCTAssertEqual(tilt?.lateralDegrees ?? 99, 0, accuracy: 1e-3)
        let plain = TiltEstimator.estimate(
            timestamp: 0,
            gravity: Pose.gravity(Pose.attitude(forward: 20, lateral: 0, mountPitch: 8, mountRoll: -3, mountYaw: 25)),
            baseline: monitor.baseline?.gravity ?? down,
            axes: .airPodsDefault
        )
        XCTAssertEqual(plain.lateralDegrees, 20 * sin(25 * rad), accuracy: 0.05)
    }

    func testNodUpWorksAndKeepsTheDefaultSign() {
        let mount = Mount(pitch: 8, roll: -3, yaw: -15)
        let monitor = calibrated(mount)
        monitor.beginAxisCalibration()
        let updates = feed(monitor, mount, from: 10.04, to: 16) { rel in (self.nod(rel - 0.5, -20), 0) }
        XCTAssertEqual(axisOutcomes(updates).first?.name, "succeeded")
        XCTAssertEqual(yaw(monitor), Pose.trueYawDegrees(pitch: 8, roll: -3, yaw: -15), accuracy: 1e-6)
        XCTAssertGreaterThan(monitor.effectiveAxes.forwardAxis.dot(HeadAxisConvention.airPodsDefault.forwardAxis), 0)
        let held = hold(monitor, mount, from: 16, to: 20, forward: -25)
        XCTAssertEqual(held.last?.tilt?.forwardDegrees ?? 0, -25, accuracy: 0.02)
        XCTAssertEqual(held.last?.state.direction, .backward)
    }

    func testInterruptAndGapFailWithSensorInterrupted() {
        let monitor = calibrated(.level)
        monitor.beginAxisCalibration()
        feed(monitor, .level, from: 10.04, to: 11) { rel in (self.nod(rel, 20), 0) }
        let update = monitor.interrupt(at: 11)
        XCTAssertEqual(update.axisCalibrationOutcome, .failed(.sensorInterrupted))
        XCTAssertEqual(update.state, .unavailable)
        XCTAssertNil(monitor.baseline?.learnedAxes)

        monitor.beginAxisCalibration()
        hold(monitor, .level, from: 12, to: 13)
        let afterGap = monitor.process(Mount.level.sample(15, forward: 0, lateral: 0, heading: 0))
        XCTAssertEqual(afterGap.axisCalibrationOutcome, .failed(.sensorInterrupted))
        XCTAssertEqual(afterGap.state, .neutral)
    }

    func testStateIsCalibratingWithNoDetectorRemindersOrEpisodes() {
        var configuration = PostureConfiguration.default
        configuration.sustainedDuration = 1
        configuration.axisCalibrationDuration = 8
        let monitor = calibrated(.level, configuration)
        monitor.beginAxisCalibration()
        let updates = hold(monitor, .level, from: 10.04, to: 18.05, forward: 25)
        for update in updates.dropLast() {
            XCTAssertEqual(update.state.kindName, "calibrating")
            XCTAssertNil(update.reminder)
            XCTAssertNil(update.completedEpisode)
        }
        XCTAssertEqual(updates[100].state.progress ?? -1, 0.5, accuracy: 1e-9)
        // The head never returned, so the attempt ends at the duration and is fitted (a held nod).
        XCTAssertEqual(axisOutcomes(updates).count, 1)
    }

    func testBeginAxisCalibrationClosesAnOpenEpisode() {
        let monitor = calibrated(.level)
        hold(monitor, .level, from: 10.04, to: 45, forward: 25)
        XCTAssertEqual(monitor.state.kindName, "sustainedTilt")
        let last = monitor.lastProcessedTimestamp
        monitor.beginAxisCalibration()
        let update = monitor.process(Mount.level.sample(45, forward: 25, lateral: 0, heading: 0))
        XCTAssertEqual(update.completedEpisode?.endTimestamp, last)
        XCTAssertEqual(update.state.kindName, "calibrating")
    }

    func testNeutralRecalibrationClearsLearnedAxesAndVersionsIncrement() {
        let mount = Mount(pitch: 0, roll: 0, yaw: 20)
        let monitor = calibrated(mount)
        monitor.beginAxisCalibration()
        feed(monitor, mount, from: 10.04, to: 16) { rel in (self.nod(rel - 0.5, 20), 0) }
        XCTAssertNotNil(monitor.baseline?.learnedAxes)
        XCTAssertEqual(monitor.baseline?.version, 2)
        monitor.beginCalibration()
        let updates = hold(monitor, mount, from: 16, to: 26.5)
        XCTAssertEqual(updates.filter { $0.calibrationOutcome != nil }.count, 1)
        XCTAssertNil(monitor.baseline?.learnedAxes)
        XCTAssertEqual(monitor.baseline?.version, 3)
        XCTAssertEqual(monitor.effectiveAxes, .airPodsDefault)
    }

    func testCancelAndClearLearnedAxes() {
        let mount = Mount(pitch: 0, roll: 0, yaw: 20)
        let monitor = calibrated(mount)
        monitor.beginAxisCalibration()
        hold(monitor, mount, from: 10.04, to: 11)
        monitor.cancelAxisCalibration()
        XCTAssertEqual(monitor.process(mount.sample(11, forward: 0, lateral: 0, heading: 0)).state, .neutral)
        XCTAssertEqual(axisOutcomes(feed(monitor, mount, from: 11.04, to: 20) { rel in (self.nod(rel, 20), 0) }).count, 0)

        monitor.beginAxisCalibration()
        feed(monitor, mount, from: 20, to: 26) { rel in (self.nod(rel - 0.5, 20), 0) }
        XCTAssertEqual(monitor.baseline?.version, 2)
        monitor.clearLearnedAxes()
        XCTAssertNil(monitor.baseline?.learnedAxes)
        XCTAssertEqual(monitor.effectiveAxes, .airPodsDefault)
        XCTAssertEqual(monitor.baseline?.version, 2)
    }

    func testNeutralAndAxisCalibrationCancelEachOther() {
        let monitor = calibrated(.level)
        monitor.beginAxisCalibration()
        hold(monitor, .level, from: 10.04, to: 11)
        monitor.beginCalibration()
        let updates = hold(monitor, .level, from: 11, to: 22)
        XCTAssertEqual(axisOutcomes(updates).count, 0)
        XCTAssertEqual(updates.filter { $0.calibrationOutcome != nil }.count, 1)

        monitor.beginCalibration()
        hold(monitor, .level, from: 22, to: 23)
        monitor.beginAxisCalibration()
        let axis = feed(monitor, .level, from: 23, to: 30) { rel in (self.nod(rel - 0.5, 20), 0) }
        XCTAssertEqual(axis.filter { $0.calibrationOutcome != nil }.count, 0)
        XCTAssertEqual(axisOutcomes(axis).count, 1)
        XCTAssertEqual(monitor.baseline?.version, 3)
    }

    func testStoredBaselineWithLearnedAxesIsUsedForTilt() {
        let learned = Pose.trueDeviceAxes(pitch: 0, roll: 0, yaw: 30)
        let stored = NeutralBaseline(gravity: down, capturedAt: Date(), sampleCount: 250, version: 4, learnedAxes: learned)
        let monitor = PostureMonitor(baseline: stored)
        XCTAssertEqual(monitor.effectiveAxes, learned)
        let updates = hold(monitor, Mount(pitch: 0, roll: 0, yaw: 30), from: 0, to: 4, lateral: 20)
        XCTAssertEqual(updates.last?.tilt?.lateralDegrees ?? 0, 20, accuracy: 1e-3)
        XCTAssertEqual(updates.last?.tilt?.forwardDegrees ?? 99, 0, accuracy: 1e-3)
    }
}
