import XCTest
import SwiftData
import AlignCore
@testable import Align

/// Sample watchdog (D-017 (c)).
final class SampleWatchdogTests: XCTestCase {
    @MainActor
    func testFiresOnceAfterTheGapAndResumesWithSamples() {
        let h = ControllerHarness()
        defer { h.finish() }
        h.connect()
        h.calibrateNeutral()
        h.feed(seconds: 2)
        XCTAssertNotNil(h.controller.latestTilt)
        XCTAssertTrue(h.timer.isRunning)
        XCTAssertEqual(h.controller.sampleStallCount, 0, "must not fire while samples flow")

        // Silence: maxSampleGap (1 s) + margin (0.5 s) must pass first.
        h.clock.now += 1.4
        h.timer.fire()
        XCTAssertEqual(h.controller.sampleStallCount, 0)
        h.clock.now += 0.2
        h.timer.fire()
        XCTAssertEqual(h.controller.sampleStallCount, 1)
        XCTAssertTrue(h.controller.isSampleStalled)
        XCTAssertNil(h.controller.latestTilt, "no stale tilt after a stall")
        XCTAssertNil(h.controller.latestSample)
        XCTAssertEqual(h.controller.postureState, .unavailable)
        XCTAssertFalse(h.timer.isRunning, "disarmed until the next sample")

        // Fires only once per silence.
        h.clock.now += 5
        h.timer.fire()
        XCTAssertEqual(h.controller.sampleStallCount, 1)

        // Samples return: normal operation resumes.
        h.feed(seconds: 1)
        XCTAssertFalse(h.controller.isSampleStalled)
        XCTAssertTrue(h.timer.isRunning)
        XCTAssertNotNil(h.controller.latestTilt)
        XCTAssertEqual(h.controller.postureState, .neutral)
        XCTAssertEqual(h.controller.sampleStallCount, 1)
    }

    @MainActor
    func testDoesNotRunWhenNotConnected() {
        let h = ControllerHarness()
        defer { h.finish() }
        h.controller.acquireSensor(.diagnostics)
        // Streaming, but the provider never reported .connected.
        h.feed(seconds: 1)
        XCTAssertFalse(h.timer.isRunning)
        h.clock.now += 10
        h.timer.fire()
        XCTAssertEqual(h.controller.sampleStallCount, 0)

        // Connected, then the AirPods go away: the timer stops with the connection.
        h.controller.handle(.connectionChanged(.connected))
        h.feed(seconds: 1)
        XCTAssertTrue(h.timer.isRunning)
        h.controller.handle(.connectionChanged(.waitingForHeadphones))
        XCTAssertFalse(h.timer.isRunning)
        h.clock.now += 10
        h.timer.fire()
        XCTAssertEqual(h.controller.sampleStallCount, 0)
    }

    @MainActor
    func testDoesNotRunWhenNotStreaming() {
        let h = ControllerHarness()
        defer { h.finish() }
        h.controller.handle(.connectionChanged(.connected))
        h.feed(seconds: 1)
        XCTAssertFalse(h.timer.isRunning)
        XCTAssertEqual(h.timer.startCount, 0)
    }

    @MainActor
    func testStopsWhenStreamingStops() {
        let h = ControllerHarness()
        defer { h.finish() }
        h.connect()
        h.feed(seconds: 1)
        XCTAssertTrue(h.timer.isRunning)
        h.controller.releaseSensor(.diagnostics)
        XCTAssertFalse(h.timer.isRunning)
    }

    @MainActor
    func testStallClosesTheOpenEpisode() throws {
        let h = ControllerHarness()
        defer { h.finish() }
        h.connect()
        h.calibrateNeutral()
        h.controller.startSession()
        XCTAssertEqual(h.controller.sessionState, .running)
        // 20° forward for longer than the 30 s hold time.
        h.feed(seconds: 36) { _ in (20, 0) }
        guard case .sustainedTilt(.forward, _) = h.controller.postureState else {
            return XCTFail("expected a sustained forward tilt, got \(h.controller.postureState)")
        }
        let context = h.environment.modelContainer.mainContext
        XCTAssertEqual(try context.fetch(FetchDescriptor<PostureEvent>()).count, 0)

        h.clock.now += 2
        h.timer.fire()
        XCTAssertEqual(h.controller.sampleStallCount, 1)
        let events = try context.fetch(FetchDescriptor<PostureEvent>())
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.deviationType, TiltDirection.forward.rawValue)
        XCTAssertEqual(h.controller.sessionState, .running, "a stall does not end the session")
    }
}

/// Guided-nod axis calibration in the app (D-017 (a)): what is stored and when it is cleared.
final class AxisCalibrationFlowTests: XCTestCase {
    @MainActor
    func testNodSuccessPersistsLearnedAxes() throws {
        let h = ControllerHarness()
        defer { h.finish() }
        h.mountYaw = 20
        h.connect()
        h.calibrateNeutral()
        XCTAssertEqual(h.controller.baseline?.version, 1)
        XCTAssertNil(h.controller.baseline?.learnedAxes)

        h.controller.startAxisCalibration()
        XCTAssertEqual(h.controller.axisCalibrationPhase, .inProgress(progress: 0))
        h.nod()

        guard case .succeeded(let axes) = h.controller.axisCalibrationPhase else {
            return XCTFail("expected a successful nod, got \(h.controller.axisCalibrationPhase)")
        }
        let stored = try XCTUnwrap(h.controller.baseline)
        XCTAssertEqual(stored.learnedAxes, axes)
        XCTAssertEqual(stored.version, 2)
        // Persisted through SettingsStore (JSON in UserDefaults).
        let reloaded = try XCTUnwrap(h.reloadedBaseline)
        XCTAssertEqual(reloaded.version, 2)
        let reloadedAxes = try XCTUnwrap(reloaded.learnedAxes)
        assertEqual(reloadedAxes.forwardAxis, axes.forwardAxis)
        assertEqual(reloadedAxes.lateralAxis, axes.lateralAxis)
        XCTAssertTrue(h.controller.hasLearnedAxes)
        XCTAssertEqual(h.controller.effectiveAxes, axes)
        let yaw = try XCTUnwrap(h.controller.learnedAxisYawDegrees)
        XCTAssertEqual(yaw, 20, accuracy: 3)
        XCTAssertFalse(h.controller.isCalibrating)
    }

    @MainActor
    func testSkipKeepsDefaultAxes() {
        let h = ControllerHarness()
        defer { h.finish() }
        h.connect()
        h.calibrateNeutral()
        h.controller.skipAxisCalibration()
        XCTAssertEqual(h.controller.axisCalibrationPhase, .skipped)
        XCTAssertNil(h.controller.baseline?.learnedAxes)
        XCTAssertNil(h.reloadedBaseline?.learnedAxes)
        XCTAssertEqual(h.controller.effectiveAxes, HeadAxisConvention.airPodsDefault)
        XCTAssertNil(h.controller.learnedAxisYawDegrees)
    }

    @MainActor
    func testSkipDuringTheNodCancelsIt() {
        let h = ControllerHarness()
        defer { h.finish() }
        h.connect()
        h.calibrateNeutral()
        h.controller.startAxisCalibration()
        h.feed(seconds: 0.4) { rel in (25 * rel, 0) }
        h.controller.skipAxisCalibration()
        XCTAssertFalse(h.controller.isCalibrating)
        // The rest of the nod no longer counts.
        h.nod()
        XCTAssertEqual(h.controller.axisCalibrationPhase, .skipped)
        XCTAssertNil(h.reloadedBaseline?.learnedAxes)
        XCTAssertEqual(h.reloadedBaseline?.version, 1)
    }

    @MainActor
    func testUseDefaultAxesClearsLearnedAxes() throws {
        let h = ControllerHarness()
        defer { h.finish() }
        h.mountYaw = 15
        h.connect()
        h.calibrateNeutral()
        h.controller.startAxisCalibration()
        h.nod()
        XCTAssertNotNil(h.reloadedBaseline?.learnedAxes)

        h.controller.useDefaultAxes()
        XCTAssertNil(h.controller.baseline?.learnedAxes)
        let reloaded = try XCTUnwrap(h.reloadedBaseline)
        XCTAssertNil(reloaded.learnedAxes)
        XCTAssertEqual(reloaded.version, 2, "clearing keeps the version")
        XCTAssertEqual(h.controller.effectiveAxes, HeadAxisConvention.airPodsDefault)
        XCTAssertFalse(h.controller.hasLearnedAxes)
    }

    @MainActor
    func testNeutralRecalibrationClearsLearnedAxes() throws {
        let h = ControllerHarness()
        defer { h.finish() }
        h.mountYaw = -15
        h.connect()
        h.calibrateNeutral()
        h.controller.startAxisCalibration()
        h.nod()
        XCTAssertNotNil(h.reloadedBaseline?.learnedAxes)

        h.calibrateNeutral()
        let reloaded = try XCTUnwrap(h.reloadedBaseline)
        XCTAssertNil(reloaded.learnedAxes)
        XCTAssertEqual(reloaded.version, 3)
        XCTAssertNil(h.controller.baseline?.learnedAxes)
        XCTAssertEqual(h.controller.baseline?.version, 3)
        XCTAssertEqual(h.controller.effectiveAxes, HeadAxisConvention.airPodsDefault)
        XCTAssertEqual(h.controller.axisCalibrationPhase, .idle)
    }

    @MainActor
    func testStillHeadReportsNoNod() {
        let h = ControllerHarness()
        defer { h.finish() }
        h.connect()
        h.calibrateNeutral()
        h.controller.startAxisCalibration()
        h.feed(seconds: 9)
        XCTAssertEqual(h.controller.axisCalibrationPhase, .failed(.noNodDetected))
        XCTAssertNil(h.reloadedBaseline?.learnedAxes)
    }

    @MainActor
    func testSidewaysTiltIsRejected() {
        let h = ControllerHarness()
        defer { h.finish() }
        h.connect()
        h.calibrateNeutral()
        h.controller.startAxisCalibration()
        h.feed(seconds: 4) { rel in
            let lateral = rel < 1 ? 25 * rel : (rel < 2 ? 25 * (2 - rel) : 0)
            return (0, lateral)
        }
        XCTAssertEqual(h.controller.axisCalibrationPhase, .failed(.inconsistentMotion))
        XCTAssertNil(h.reloadedBaseline?.learnedAxes)
    }

    @MainActor
    func testNodWithoutBaselineNeedsBaseline() {
        let h = ControllerHarness()
        defer { h.finish() }
        h.connect()
        h.controller.startAxisCalibration()
        XCTAssertEqual(h.controller.axisCalibrationPhase, .failed(.needsBaseline))
        XCTAssertFalse(h.controller.isCalibrating)
    }

    @MainActor
    func testDisconnectDuringTheNodReportsInterruption() {
        let h = ControllerHarness()
        defer { h.finish() }
        h.connect()
        h.calibrateNeutral()
        h.controller.startAxisCalibration()
        h.feed(seconds: 0.5) { rel in (25 * rel, 0) }
        h.controller.handle(.connectionChanged(.waitingForHeadphones))
        XCTAssertEqual(h.controller.axisCalibrationPhase, .failed(.sensorInterrupted))
        XCTAssertNil(h.reloadedBaseline?.learnedAxes)
    }

    private func assertEqual(_ a: Vector3, _ b: Vector3, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(a.z, b.z, accuracy: 1e-9, file: file, line: line)
    }
}
