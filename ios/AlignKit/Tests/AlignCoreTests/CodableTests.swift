import Foundation
import XCTest
@testable import AlignCore

/// Codable round trips for the AlignCore types that are persisted (UserDefaults JSON) or
/// replayed from fixtures. Values are exactly representable in binary floating point so the
/// comparisons can be exact on every platform.
final class CodableRoundTripTests: XCTestCase {
    private func roundTrip<T: Codable & Equatable>(
        _ value: T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> T {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(T.self, from: data)
        XCTAssertEqual(decoded, value, file: file, line: line)
        return decoded
    }

    private func jsonKeys<T: Encodable>(_ value: T) throws -> Set<String> {
        let data = try JSONEncoder().encode(value)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return Set(object.keys)
    }

    private let fullSample = MotionSample(
        timestamp: 12_345.625,
        attitude: Quaternion(x: 0.5, y: -0.5, z: 0.5, w: 0.5),
        gravity: Vector3(x: 0, y: -0.25, z: -0.96875),
        rotationRate: Vector3(x: 0.125, y: -0.0625, z: 0),
        userAcceleration: Vector3(x: -0.015625, y: 0.03125, z: 0.5),
        sensorLocation: .headphoneLeft
    )

    // MARK: MotionSample

    func testMotionSampleRoundTripWithAllFields() throws {
        _ = try roundTrip(fullSample)
    }

    func testMotionSampleRoundTripWithOptionalsNil() throws {
        let sample = MotionSample(timestamp: 1.5, attitude: Quaternion.identity)
        let decoded = try roundTrip(sample)
        XCTAssertNil(decoded.gravity)
        XCTAssertNil(decoded.rotationRate)
        XCTAssertNil(decoded.userAcceleration)
        XCTAssertEqual(decoded.sensorLocation, .unknown)
    }

    func testMotionSampleJSONKeys() throws {
        XCTAssertEqual(
            try jsonKeys(fullSample),
            ["timestamp", "attitude", "gravity", "rotationRate", "userAcceleration", "sensorLocation"]
        )
        // Nil optionals are omitted, not encoded as null.
        XCTAssertEqual(
            try jsonKeys(MotionSample(timestamp: 0, attitude: Quaternion.identity)),
            ["timestamp", "attitude", "sensorLocation"]
        )
    }

    func testMotionSampleDecodesHandWrittenJSON() throws {
        // Shape a fixture or Python tool would write. Optional vectors may be absent.
        let json = """
        {
          "timestamp": 100.5,
          "attitude": { "x": 0, "y": 0, "z": 0, "w": 1 },
          "gravity": { "x": 0, "y": 0, "z": -1 },
          "sensorLocation": "headphoneRight"
        }
        """
        let sample = try JSONDecoder().decode(MotionSample.self, from: Data(json.utf8))
        XCTAssertEqual(sample.timestamp, 100.5)
        XCTAssertEqual(sample.attitude, Quaternion.identity)
        XCTAssertEqual(sample.gravity, Vector3(x: 0, y: 0, z: -1))
        XCTAssertNil(sample.rotationRate)
        XCTAssertNil(sample.userAcceleration)
        XCTAssertEqual(sample.sensorLocation, .headphoneRight)
    }

    func testMotionSampleRejectsUnknownSensorLocation() {
        let json = """
        { "timestamp": 1, "attitude": { "x": 0, "y": 0, "z": 0, "w": 1 }, "sensorLocation": "chin" }
        """
        XCTAssertThrowsError(try JSONDecoder().decode(MotionSample.self, from: Data(json.utf8)))
    }

    // MARK: PostureConfiguration

    func testPostureConfigurationDefaultRoundTrip() throws {
        let decoded = try roundTrip(PostureConfiguration.default)
        XCTAssertNil(decoded.maxProcessingRateHz)
    }

    func testPostureConfigurationCustomRoundTrip() throws {
        var config = PostureConfiguration()
        config.calibrationDuration = 12.5
        config.forwardThresholdDegrees = 22.5
        config.lateralThresholdDegrees = 17.25
        config.hysteresisDegrees = 2.5
        config.sustainedDuration = 45
        config.reminderCooldown = 600
        config.maxProcessingRateHz = 12.5
        config.axes = HeadAxisConvention(
            forwardAxis: Vector3(x: -1, y: 0, z: 0),
            lateralAxis: Vector3(x: 0, y: 0, z: 1)
        )
        let decoded = try roundTrip(config)
        XCTAssertEqual(decoded.maxProcessingRateHz, 12.5)
        XCTAssertEqual(decoded.axes.forwardAxis, Vector3(x: -1, y: 0, z: 0))
        XCTAssertNotEqual(decoded, PostureConfiguration.default)
    }

    func testPostureConfigurationJSONKeys() throws {
        // If this fails you added, renamed or removed a field. Settings are stored as JSON in
        // UserDefaults and the synthesized decoder requires every non-optional key, so make sure
        // JSON written by the previous version still decodes (or migrate it), then update this list.
        var config = PostureConfiguration()
        config.maxProcessingRateHz = 25
        XCTAssertEqual(try jsonKeys(config), [
            "calibrationDuration",
            "calibrationMaxSpreadDegrees",
            "minimumCalibrationSamples",
            "forwardThresholdDegrees",
            "backwardThresholdDegrees",
            "lateralThresholdDegrees",
            "hysteresisDegrees",
            "sustainedDuration",
            "reminderCooldown",
            "smoothingTimeConstant",
            "maxProcessingRateHz",
            "maxSampleGap",
            "axes",
        ])
    }

    // MARK: NeutralBaseline

    func testNeutralBaselineRoundTrip() throws {
        let baseline = NeutralBaseline(
            gravity: Vector3(x: 0.125, y: -0.25, z: -0.9375),
            capturedAt: Date(timeIntervalSinceReferenceDate: 815_000_000.5),
            sampleCount: 250,
            version: 3
        )
        let decoded = try roundTrip(baseline)
        XCTAssertEqual(decoded.capturedAt, baseline.capturedAt)
        XCTAssertEqual(decoded.version, 3)
    }

    func testNeutralBaselineJSONKeys() throws {
        let baseline = NeutralBaseline(
            gravity: Vector3(x: 0, y: 0, z: -1),
            capturedAt: Date(timeIntervalSinceReferenceDate: 0),
            sampleCount: 100,
            version: 1
        )
        XCTAssertEqual(try jsonKeys(baseline), ["gravity", "capturedAt", "sampleCount", "version"])
    }

    // MARK: Smaller Codable types

    func testHeadAxisConventionAndTiltEstimateRoundTrip() throws {
        _ = try roundTrip(HeadAxisConvention.airPodsDefault)
        _ = try roundTrip(TiltEstimate(timestamp: 3.25, forwardDegrees: 18.5, lateralDegrees: -4.75, totalDegrees: 19.125))
    }
}

/// String raw values that are persisted (PostureEvent.deviationType, settings, fixtures).
/// Changing any of them breaks stored data and shared fixtures.
final class PersistedRawValueTests: XCTestCase {
    func testTiltDirectionRawValues() {
        XCTAssertEqual(TiltDirection.allCases.map(\.rawValue), ["forward", "backward", "left", "right"])
    }

    func testSensorLocationRawValues() {
        XCTAssertEqual(SensorLocation.unknown.rawValue, "unknown")
        XCTAssertEqual(SensorLocation.headphoneLeft.rawValue, "headphoneLeft")
        XCTAssertEqual(SensorLocation.headphoneRight.rawValue, "headphoneRight")
    }

    func testCalibrationFailureRawValues() {
        XCTAssertEqual(CalibrationFailure.tooMuchMovement.rawValue, "tooMuchMovement")
        XCTAssertEqual(CalibrationFailure.insufficientSamples.rawValue, "insufficientSamples")
        XCTAssertEqual(CalibrationFailure.sensorInterrupted.rawValue, "sensorInterrupted")
    }

    func testSensorEnumsRawValues() {
        XCTAssertEqual(SensorAuthorization.denied.rawValue, "denied")
        XCTAssertEqual(SensorUnavailableReason.motionNotSupported.rawValue, "motionNotSupported")
        XCTAssertEqual(SensorUnavailableReason.notAuthorized.rawValue, "notAuthorized")
    }
}

/// Sanity checks on contract defaults. These are experimental values (not medically validated);
/// the tests only guard internal consistency.
final class ContractDefaultsTests: XCTestCase {
    func testDefaultConfigurationIsConsistent() {
        let c = PostureConfiguration.default
        XCTAssertGreaterThan(c.hysteresisDegrees, 0)
        for threshold in [c.forwardThresholdDegrees, c.backwardThresholdDegrees, c.lateralThresholdDegrees] {
            XCTAssertGreaterThan(threshold, c.hysteresisDegrees, "hysteresis must leave a positive release threshold")
            // A calibration that accepts this much spread must not already be a deviation.
            XCTAssertLessThan(c.calibrationMaxSpreadDegrees, threshold)
        }
        XCTAssertGreaterThan(c.calibrationDuration, 0)
        XCTAssertGreaterThan(c.sustainedDuration, 0)
        XCTAssertGreaterThan(c.reminderCooldown, 0)
        XCTAssertGreaterThan(c.smoothingTimeConstant, 0)
        XCTAssertGreaterThan(c.maxSampleGap, 0)
        // Must be reachable at the mock's default 25 Hz (AirPods rate is unverified, see S-05).
        XCTAssertLessThanOrEqual(Double(c.minimumCalibrationSamples), c.calibrationDuration * 25)
    }

    func testAirPodsDefaultAxesAreOrthonormal() {
        let axes = HeadAxisConvention.airPodsDefault
        XCTAssertEqual(axes.forwardAxis.length, 1, accuracy: 1e-12)
        XCTAssertEqual(axes.lateralAxis.length, 1, accuracy: 1e-12)
        XCTAssertEqual(axes.forwardAxis.dot(axes.lateralAxis), 0, accuracy: 1e-12)
    }
}
