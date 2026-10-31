import AlignCore
import XCTest
@testable import Sensors

final class MockMotionGeneratorTests: XCTestCase {
    private let sin20 = sin(20 * Double.pi / 180)
    private let cos20 = cos(20 * Double.pi / 180)

    // MARK: - Determinism

    func testSameSeedProducesIdenticalSamples() {
        let a = MockMotionGenerator(scenario: .gradualForwardSlouch)
        let b = MockMotionGenerator(scenario: .gradualForwardSlouch)
        for index in stride(from: 0, to: 3000, by: 7) {
            XCTAssertEqual(
                a.sample(index: index, startTimestamp: 500),
                b.sample(index: index, startTimestamp: 500),
                "index \(index)"
            )
        }
    }

    func testRepeatedQueriesAreStable() {
        let generator = MockMotionGenerator(scenario: .briefGlanceDown)
        let first = generator.sample(at: 12.34, timestamp: 1)
        let second = generator.sample(at: 12.34, timestamp: 1)
        XCTAssertEqual(first, second)
    }

    func testDifferentSeedsProduceDifferentNoise() {
        let a = MockMotionGenerator(scenario: .steadyNeutral, seed: 1)
        let b = MockMotionGenerator(scenario: .steadyNeutral, seed: 2)
        XCTAssertNotEqual(a.sample(at: 3, timestamp: 0).gravity, b.sample(at: 3, timestamp: 0).gravity)
    }

    func testTimestampsFollowSampleRate() {
        let generator = MockMotionGenerator(scenario: .steadyNeutral, sampleRateHz: 25)
        let s0 = generator.sample(index: 0, startTimestamp: 100)
        let s25 = generator.sample(index: 25, startTimestamp: 100)
        XCTAssertEqual(s0?.timestamp ?? 0, 100, accuracy: 1e-9)
        XCTAssertEqual(s25?.timestamp ?? 0, 101, accuracy: 1e-9)
    }

    // MARK: - Geometry and axis convention

    func testForwardPoseGravityMatchesAxisConvention() {
        let attitude = MockMotionGenerator.attitude(
            for: MockHeadPose(forwardDegrees: 20),
            axes: .airPodsDefault
        )
        let gravity = MockMotionGenerator.gravity(forAttitude: attitude)

        // +20° head rotation about +X (forwardAxis): head-frame gravity tips toward −Y.
        XCTAssertEqual(gravity.x, 0, accuracy: 1e-12)
        XCTAssertEqual(gravity.y, -sin20, accuracy: 1e-12)
        XCTAssertEqual(gravity.z, -cos20, accuracy: 1e-12)
        XCTAssertEqual(gravity.length, 1, accuracy: 1e-12)

        // The attitude is a +20° rotation about forwardAxis.
        let rotation = MockMotionGenerator.rotationVector(of: attitude)
        XCTAssertEqual(rotation.dot(HeadAxisConvention.airPodsDefault.forwardAxis), 20 * Double.pi / 180, accuracy: 1e-12)

        let tilt = TiltReference.headTiltDegrees(gravity: gravity)
        XCTAssertEqual(tilt.forward, 20, accuracy: 1e-9)
        XCTAssertEqual(tilt.lateral, 0, accuracy: 1e-9)
    }

    func testLateralPoseGravityMatchesAxisConvention() {
        let attitude = MockMotionGenerator.attitude(
            for: MockHeadPose(lateralDegrees: 20),
            axes: .airPodsDefault
        )
        let gravity = MockMotionGenerator.gravity(forAttitude: attitude)

        // +20° head rotation about +Y (lateralAxis): head-frame gravity tips toward +X.
        XCTAssertEqual(gravity.x, sin20, accuracy: 1e-12)
        XCTAssertEqual(gravity.y, 0, accuracy: 1e-12)
        XCTAssertEqual(gravity.z, -cos20, accuracy: 1e-12)

        let tilt = TiltReference.headTiltDegrees(gravity: gravity)
        XCTAssertEqual(tilt.forward, 0, accuracy: 1e-9)
        XCTAssertEqual(tilt.lateral, 20, accuracy: 1e-9)
    }

    func testAttitudeMapsHeadGravityBackToWorldDown() {
        let attitude = MockMotionGenerator.attitude(
            for: MockHeadPose(forwardDegrees: 12, lateralDegrees: -7, headingDegrees: 70),
            axes: .airPodsDefault
        )
        let headGravity = MockMotionGenerator.gravity(forAttitude: attitude)
        let worldGravity = attitude.rotate(headGravity)
        XCTAssertEqual(worldGravity.x, 0, accuracy: 1e-12)
        XCTAssertEqual(worldGravity.y, 0, accuracy: 1e-12)
        XCTAssertEqual(worldGravity.z, -1, accuracy: 1e-12)
    }

    func testHeadingDoesNotChangeGravityOrTilt() {
        let axes = HeadAxisConvention.airPodsDefault
        let reference = MockMotionGenerator.gravity(
            forAttitude: MockMotionGenerator.attitude(for: MockHeadPose(forwardDegrees: 15, lateralDegrees: -10), axes: axes)
        )
        for heading in [-120.0, -30, 45, 170] {
            let turnedAttitude = MockMotionGenerator.attitude(
                for: MockHeadPose(forwardDegrees: 15, lateralDegrees: -10, headingDegrees: heading),
                axes: axes
            )
            let gravity = MockMotionGenerator.gravity(forAttitude: turnedAttitude)
            XCTAssertEqual(gravity.x, reference.x, accuracy: 1e-12)
            XCTAssertEqual(gravity.y, reference.y, accuracy: 1e-12)
            XCTAssertEqual(gravity.z, reference.z, accuracy: 1e-12)
            let tilt = TiltReference.headTiltDegrees(gravity: gravity)
            XCTAssertEqual(tilt.forward, 15, accuracy: 1e-9)
            XCTAssertEqual(tilt.lateral, -10, accuracy: 1e-9)
        }
    }

    func testAlternativeAxisConventionIsHonoured() {
        // If hardware shows a different sign (e.g. +X toward the right ear, +Y toward the
        // nose, so chin-down is a rotation about −X), the mock must follow the convention:
        // a +20° forward pose still reads +20° under that convention.
        let flipped = HeadAxisConvention(
            forwardAxis: Vector3(x: -1, y: 0, z: 0),
            lateralAxis: Vector3(x: 0, y: 1, z: 0)
        )
        var generator = MockMotionGenerator(scenario: .manual, axes: flipped, noiseScale: 0)
        generator.manualPose = MockHeadPose(forwardDegrees: 20, lateralDegrees: 5)
        let gravity = generator.sample(at: 1, timestamp: 1).gravity ?? .zero
        let tilt = TiltReference.headTiltDegrees(gravity: gravity, axes: flipped)
        XCTAssertEqual(tilt.forward, 20, accuracy: 1e-9)
        XCTAssertEqual(tilt.lateral, 5, accuracy: 1e-9)
    }

    func testEverySampleHasUnitGravityAndAllFields() {
        let generator = MockMotionGenerator(scenario: .gradualForwardSlouch)
        for index in stride(from: 0, to: 3000, by: 13) {
            guard let sample = generator.sample(index: index, startTimestamp: 0) else {
                XCTFail("missing sample at \(index)")
                continue
            }
            XCTAssertEqual(sample.gravity?.length ?? 0, 1, accuracy: 1e-9)
            XCTAssertNotNil(sample.rotationRate)
            XCTAssertNotNil(sample.userAcceleration)
            XCTAssertEqual(sample.attitude.norm, 1, accuracy: 1e-9)
        }
    }

    // MARK: - Scenario timelines

    func testGradualForwardSlouchTimeline() {
        let generator = MockMotionGenerator(scenario: .gradualForwardSlouch)
        XCTAssertEqual(generator.basePose(at: 10).forwardDegrees, 0, accuracy: 1e-12)
        XCTAssertEqual(generator.basePose(at: 30).forwardDegrees, 25, accuracy: 1e-9)
        XCTAssertEqual(generator.basePose(at: 60).forwardDegrees, 25, accuracy: 1e-12)
        XCTAssertEqual(generator.basePose(at: 89.9).forwardDegrees, 25, accuracy: 1e-12)
        XCTAssertEqual(generator.basePose(at: 100).forwardDegrees, 0, accuracy: 1e-12)
        // Monotonic drift between 20 s and 30 s.
        var previous = -1.0
        for step in 0...100 {
            let value = generator.basePose(at: 20 + Double(step) * 0.1).forwardDegrees
            XCTAssertGreaterThanOrEqual(value, previous)
            previous = value
        }

        // With noise, the measured tilt stays within ~1° of the script.
        let neutral = TiltReference.headTiltDegrees(gravity: generator.sample(at: 10, timestamp: 0).gravity ?? .zero)
        XCTAssertEqual(neutral.forward, 0, accuracy: 1.5)
        let slouched = TiltReference.headTiltDegrees(gravity: generator.sample(at: 60, timestamp: 0).gravity ?? .zero)
        XCTAssertEqual(slouched.forward, 25, accuracy: 1.5)
        XCTAssertEqual(slouched.lateral, 0, accuracy: 1.5)
    }

    func testNoisyTiltStaysCloseToScriptOverWholeCycle() {
        let generator = MockMotionGenerator(scenario: .gradualForwardSlouch, sampleRateHz: 25)
        var worst = 0.0
        for index in 0..<(25 * 120) {
            let t = generator.time(ofSample: index)
            guard let sample = generator.sample(index: index, startTimestamp: 0) else { continue }
            let tilt = TiltReference.headTiltDegrees(gravity: sample.gravity ?? .zero)
            worst = max(worst, abs(tilt.forward - generator.basePose(at: t).forwardDegrees), abs(tilt.lateral))
        }
        XCTAssertLessThan(worst, 1.5)
        XCTAssertGreaterThan(worst, 0.05, "noise should be present")
    }

    func testBriefGlanceDownGlancesAreShortAndDeep() {
        let generator = MockMotionGenerator(scenario: .briefGlanceDown)
        let dt = 0.04
        var maxForward = 0.0
        var runStart: Double?
        var runLengths: [Double] = []
        var t = 0.0
        while t < 90 {
            let forward = generator.basePose(at: t).forwardDegrees
            maxForward = max(maxForward, forward)
            if forward > 1 {
                if runStart == nil { runStart = t }
            } else if let start = runStart {
                runLengths.append(t - start)
                runStart = nil
            }
            t += dt
        }
        XCTAssertEqual(maxForward, 30, accuracy: 1e-9)
        XCTAssertEqual(runLengths.count, 6) // one glance per 15 s
        for length in runLengths {
            XCTAssertGreaterThan(length, 2.5)
            XCTAssertLessThanOrEqual(length, 5.0)
        }
    }

    func testLateralTiltHoldsTwentyDegreesRight() {
        let generator = MockMotionGenerator(scenario: .lateralTilt)
        XCTAssertEqual(generator.basePose(at: 5).lateralDegrees, 0, accuracy: 1e-12)
        XCTAssertEqual(generator.basePose(at: 18).lateralDegrees, 20, accuracy: 1e-9)
        XCTAssertEqual(generator.basePose(at: 40).lateralDegrees, 20, accuracy: 1e-12)
        XCTAssertEqual(generator.basePose(at: 62.9).lateralDegrees, 20, accuracy: 1e-12)
        XCTAssertEqual(generator.basePose(at: 70).lateralDegrees, 0, accuracy: 1e-12)
        XCTAssertEqual(generator.basePose(at: 40).forwardDegrees, 0, accuracy: 1e-12)

        let tilt = TiltReference.headTiltDegrees(gravity: generator.sample(at: 40, timestamp: 0).gravity ?? .zero)
        XCTAssertEqual(tilt.lateral, 20, accuracy: 1.5)
        XCTAssertEqual(tilt.forward, 0, accuracy: 1.5)
    }

    func testSteadyNeutralTurnsHeadButDoesNotTilt() {
        let generator = MockMotionGenerator(scenario: .steadyNeutral)
        XCTAssertEqual(generator.basePose(at: 10).headingDegrees, 20, accuracy: 1e-9)
        for t in stride(from: 0.0, to: 80, by: 0.5) {
            let tilt = TiltReference.headTiltDegrees(gravity: generator.sample(at: t, timestamp: 0).gravity ?? .zero)
            XCTAssertEqual(tilt.forward, 0, accuracy: 1.5)
            XCTAssertEqual(tilt.lateral, 0, accuracy: 1.5)
        }
    }

    func testDisconnectMidSessionTimeline() {
        let generator = MockMotionGenerator(scenario: .disconnectMidSession, sampleRateHz: 25)
        XCTAssertEqual(generator.connectionState(at: 0), .connected)
        XCTAssertEqual(generator.connectionState(at: 19.96), .connected)
        XCTAssertEqual(generator.connectionState(at: 20), .waitingForHeadphones)
        XCTAssertEqual(generator.connectionState(at: 29.96), .waitingForHeadphones)
        XCTAssertEqual(generator.connectionState(at: 30), .connected)
        XCTAssertEqual(generator.connectionState(at: 500), .connected)

        XCTAssertNotNil(generator.sample(index: 25 * 10, startTimestamp: 0))
        XCTAssertNil(generator.sample(index: 25 * 25, startTimestamp: 0))
        XCTAssertNotNil(generator.sample(index: 25 * 35, startTimestamp: 0))

        XCTAssertEqual(generator.sample(index: 25 * 10, startTimestamp: 0)?.sensorLocation, .headphoneLeft)
        XCTAssertEqual(generator.sample(index: 25 * 35, startTimestamp: 0)?.sensorLocation, .headphoneRight)
    }

    func testUnavailableScenariosProduceNoSamples() {
        let unavailable = MockMotionGenerator(scenario: .unavailable)
        XCTAssertEqual(unavailable.connectionState(at: 0), .unavailable(.motionNotSupported))
        XCTAssertFalse(unavailable.producesSamples)
        XCTAssertNil(unavailable.sample(index: 10, startTimestamp: 0))

        let denied = MockMotionGenerator(scenario: .permissionDenied)
        XCTAssertEqual(denied.connectionState(at: 0), .unavailable(.notAuthorized))
        XCTAssertFalse(denied.producesSamples)
        XCTAssertNil(denied.sample(index: 10, startTimestamp: 0))
    }

    func testManualPoseIsUsed() {
        var generator = MockMotionGenerator(scenario: .manual, noiseScale: 0)
        generator.manualPose = MockHeadPose(forwardDegrees: -8, lateralDegrees: 12)
        let tilt = TiltReference.headTiltDegrees(gravity: generator.sample(at: 2, timestamp: 0).gravity ?? .zero)
        XCTAssertEqual(tilt.forward, -8, accuracy: 1e-9)
        XCTAssertEqual(tilt.lateral, 12, accuracy: 1e-9)
    }

    // MARK: - Rotation rate

    func testRotationRateReflectsForwardDrift() {
        // During the 20–30 s drift the head rotates about +forwardAxis, so the head-frame
        // rotation rate has a positive forward component.
        let generator = MockMotionGenerator(scenario: .gradualForwardSlouch, noiseScale: 0)
        let rate = generator.sample(at: 25, timestamp: 0).rotationRate ?? .zero
        // smoothstep peak slope: 1.5 × 25° / 10 s = 3.75 °/s.
        let expected = 3.75 * Double.pi / 180
        XCTAssertEqual(rate.dot(HeadAxisConvention.airPodsDefault.forwardAxis), expected, accuracy: expected * 0.05)

        let still = generator.sample(at: 60, timestamp: 0).rotationRate ?? Vector3(x: 1, y: 1, z: 1)
        XCTAssertEqual(still.length, 0, accuracy: 1e-9)
    }
}
