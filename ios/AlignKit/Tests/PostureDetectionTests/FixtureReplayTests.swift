import Foundation
import XCTest
import AlignCore
@testable import PostureDetection

// MARK: - Fixture model (format: shared/fixtures/README.md)

struct MotionFixture: Decodable {
    let schemaVersion: Int
    let name: String
    let sampleRateHz: Double
    let config: FixtureConfig?
    let baseline: FixtureBaseline?
    let actions: [FixtureAction]?
    let expected: FixtureExpected
    let reference: FixtureReference
    let samples: [FixtureSample]
}

struct FixtureConfig: Decodable {
    let calibrationDuration: Double?
    let calibrationMaxSpreadDegrees: Double?
    let calibrationSpreadQuantile: Double?
    let calibrationMaxDriftDegrees: Double?
    let calibrationDriftWindow: Double?
    let minimumCalibrationSamples: Int?
    let forwardThresholdDegrees: Double?
    let backwardThresholdDegrees: Double?
    let lateralThresholdDegrees: Double?
    let hysteresisDegrees: Double?
    let sustainedDuration: Double?
    let reminderCooldown: Double?
    let smoothingTimeConstant: Double?
    let maxProcessingRateHz: Double?
    let maxSampleGap: Double?
    let forwardAxis: [Double]?
    let lateralAxis: [Double]?
    let axisCalibrationDuration: Double?
    let axisCalibrationMinimumNodDegrees: Double?
    let axisCalibrationMaxYawDegrees: Double?
    let axisCalibrationMaxOffAxisRatio: Double?

    func configuration() -> PostureConfiguration {
        var c = PostureConfiguration.default
        if let v = calibrationDuration { c.calibrationDuration = v }
        if let v = calibrationMaxSpreadDegrees { c.calibrationMaxSpreadDegrees = v }
        if let v = calibrationSpreadQuantile { c.calibrationSpreadQuantile = v }
        if let v = calibrationMaxDriftDegrees { c.calibrationMaxDriftDegrees = v }
        if let v = calibrationDriftWindow { c.calibrationDriftWindow = v }
        if let v = minimumCalibrationSamples { c.minimumCalibrationSamples = v }
        if let v = forwardThresholdDegrees { c.forwardThresholdDegrees = v }
        if let v = backwardThresholdDegrees { c.backwardThresholdDegrees = v }
        if let v = lateralThresholdDegrees { c.lateralThresholdDegrees = v }
        if let v = hysteresisDegrees { c.hysteresisDegrees = v }
        if let v = sustainedDuration { c.sustainedDuration = v }
        if let v = reminderCooldown { c.reminderCooldown = v }
        if let v = smoothingTimeConstant { c.smoothingTimeConstant = v }
        if let v = maxProcessingRateHz { c.maxProcessingRateHz = v }
        if let v = maxSampleGap { c.maxSampleGap = v }
        if let v = forwardAxis, v.count == 3 { c.axes.forwardAxis = Vector3(x: v[0], y: v[1], z: v[2]) }
        if let v = lateralAxis, v.count == 3 { c.axes.lateralAxis = Vector3(x: v[0], y: v[1], z: v[2]) }
        if let v = axisCalibrationDuration { c.axisCalibrationDuration = v }
        if let v = axisCalibrationMinimumNodDegrees { c.axisCalibrationMinimumNodDegrees = v }
        if let v = axisCalibrationMaxYawDegrees { c.axisCalibrationMaxYawDegrees = v }
        if let v = axisCalibrationMaxOffAxisRatio { c.axisCalibrationMaxOffAxisRatio = v }
        return c
    }
}

struct FixtureAxes: Decodable {
    let forwardAxis: [Double]
    let lateralAxis: [Double]

    var convention: HeadAxisConvention? {
        guard forwardAxis.count == 3, lateralAxis.count == 3 else { return nil }
        return HeadAxisConvention(
            forwardAxis: Vector3(x: forwardAxis[0], y: forwardAxis[1], z: forwardAxis[2]),
            lateralAxis: Vector3(x: lateralAxis[0], y: lateralAxis[1], z: lateralAxis[2])
        )
    }
}

struct FixtureBaseline: Decodable {
    let gravity: [Double]
    let version: Int?
    let sampleCount: Int?
    let learnedAxes: FixtureAxes?
}

struct FixtureAction: Decodable {
    let t: Double
    let type: String
}

struct FixtureSample: Decodable {
    let t: Double
    let q: [Double]
    let g: [Double]?
    let r: [Double]?
}

struct FixtureExpected: Decodable {
    struct Reminder: Decodable {
        let t: Double
        let direction: String
    }

    struct Episode: Decodable {
        let direction: String
        let start: Double
        let end: Double
        let reminderTriggered: Bool
    }

    struct Tolerances: Decodable {
        let timeSeconds: Double
    }

    /// D-017: whether the replay ends with learned axes, and their yaw from the configured axes.
    struct LearnedAxes: Decodable {
        let present: Bool
        let yawDegrees: Double?
        let toleranceDegrees: Double?
    }

    /// D-017: |tilt.lateralDegrees| <= degrees for every update with from <= t <= to.
    struct LateralBound: Decodable {
        let from: Double
        let to: Double
        let degrees: Double
    }

    let calibrationOutcomes: [String]
    let reminders: [Reminder]
    let episodes: [Episode]
    let finalState: String
    let tolerances: Tolerances
    let axisCalibrationOutcomes: [String]?
    let learnedAxes: LearnedAxes?
    let maxAbsLateral: LateralBound?
}

struct FixtureReference: Decodable {
    struct Reminder: Decodable {
        let t: Double
        let direction: String
        let deviationDegrees: Double
        let sustainedSeconds: Double
    }

    struct Episode: Decodable {
        let direction: String
        let start: Double
        let end: Double
        let peakDeviationDegrees: Double
        let reminderTriggered: Bool
    }

    let calibrationOutcomes: [String]
    /// Present (with `learnedAxes`, possibly null) only when an axis calibration finished.
    let axisCalibrationOutcomes: [String]?
    let learnedAxes: FixtureAxes?
    let reminders: [Reminder]
    let episodes: [Episode]
    let finalState: String
    let stateTransitions: Int
}

// MARK: - Replay (mirrors `Fixtures.replay` in `analytics/align-tools`)

struct ReplayResult {
    var reminders: [ReminderDecision] = []
    var episodes: [PostureEpisode] = []
    var calibrationOutcomes: [String] = []
    var axisCalibrationOutcomes: [String] = []
    var finalState = ""
    var stateTransitions = 0
    var tilts: [TiltEstimate] = []
    var finalBaseline: NeutralBaseline?
    var configuration = PostureConfiguration.default

    var learnedAxes: HeadAxisConvention? { finalBaseline?.learnedAxes }

    /// Signed yaw (degrees) of the learned forward axis from `configuration.axes`, or nil.
    var learnedYawDegrees: Double? {
        guard let learned = learnedAxes, let b = finalBaseline else { return nil }
        return AxisCalibrationService.signedYawDegrees(
            forwardAxis: learned.forwardAxis,
            baselineGravity: b.gravity,
            reference: configuration.axes
        )
    }

    /// Largest |lateralDegrees| of the tilts with from <= t <= to (0 if none).
    func maxAbsLateralDegrees(from: Double, to: Double) -> Double {
        tilts.filter { $0.timestamp >= from && $0.timestamp <= to }.map { abs($0.lateralDegrees) }.max() ?? 0
    }
}

enum FixtureReplay {
    static func fixtureDirectory(file: String = #filePath) -> URL? {
        // ios/AlignKit/Tests/PostureDetectionTests/<file>.swift → repo root is 5 levels up;
        // walk up defensively in case the layout changes.
        var dir = URL(fileURLWithPath: file).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir.appendingPathComponent("shared/fixtures/motion", isDirectory: true)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    static func load(_ name: String) throws -> MotionFixture {
        guard let dir = fixtureDirectory() else {
            throw NSError(domain: "FixtureReplay", code: 1, userInfo: [NSLocalizedDescriptionKey: "shared/fixtures/motion not found"])
        }
        let data = try Data(contentsOf: dir.appendingPathComponent("\(name).json"))
        return try JSONDecoder().decode(MotionFixture.self, from: data)
    }

    static func sample(_ s: FixtureSample) -> MotionSample {
        let q = s.q.count == 4 ? Quaternion(x: s.q[0], y: s.q[1], z: s.q[2], w: s.q[3]) : Quaternion.identity
        var gravity: Vector3?
        if let g = s.g, g.count == 3 {
            gravity = Vector3(x: g[0], y: g[1], z: g[2])
        }
        var rotationRate: Vector3?
        if let r = s.r, r.count == 3 {
            rotationRate = Vector3(x: r[0], y: r[1], z: r[2])
        }
        return MotionSample(timestamp: s.t, attitude: q, gravity: gravity, rotationRate: rotationRate)
    }

    static func replay(_ fixture: MotionFixture, configuration override: PostureConfiguration? = nil) -> ReplayResult {
        let configuration = override ?? fixture.config?.configuration() ?? .default
        var baseline: NeutralBaseline?
        if let b = fixture.baseline, b.gravity.count == 3 {
            baseline = NeutralBaseline(
                gravity: Vector3(x: b.gravity[0], y: b.gravity[1], z: b.gravity[2]),
                capturedAt: Date(timeIntervalSince1970: 0),
                sampleCount: b.sampleCount ?? 0,
                version: b.version ?? 1,
                learnedAxes: b.learnedAxes?.convention
            )
        }
        let monitor = PostureMonitor(configuration: configuration, baseline: baseline)
        // Stable sort by t, like the reference replay.
        let actions = (fixture.actions ?? []).enumerated()
            .sorted { lhs, rhs in lhs.element.t != rhs.element.t ? lhs.element.t < rhs.element.t : lhs.offset < rhs.offset }
            .map { $0.element }
        var result = ReplayResult()
        result.configuration = configuration
        var previousKind: String?

        func record(_ update: PostureUpdate) {
            if let reminder = update.reminder {
                result.reminders.append(reminder)
            }
            if let episode = update.completedEpisode {
                result.episodes.append(episode)
            }
            if let outcome = update.calibrationOutcome {
                result.calibrationOutcomes.append(outcome.name)
            }
            if let outcome = update.axisCalibrationOutcome {
                result.axisCalibrationOutcomes.append(outcome.name)
            }
            if let tilt = update.tilt {
                result.tilts.append(tilt)
            }
            let kind = update.state.kindName
            if let previous = previousKind, previous != kind {
                result.stateTransitions += 1
            }
            previousKind = kind
        }

        func apply(_ action: FixtureAction) {
            switch action.type {
            case "beginCalibration":
                monitor.beginCalibration()
            case "cancelCalibration":
                monitor.cancelCalibration()
            case "beginAxisCalibration":
                monitor.beginAxisCalibration()
            case "cancelAxisCalibration":
                monitor.cancelAxisCalibration()
            case "clearLearnedAxes":
                monitor.clearLearnedAxes()
            case "resetCooldown":
                monitor.resetCooldown()
            case "interrupt":
                record(monitor.interrupt(at: action.t))
            default:
                XCTFail("unknown action type \(action.type)")
            }
        }

        var index = 0
        for s in fixture.samples {
            while index < actions.count && actions[index].t <= s.t {
                apply(actions[index])
                index += 1
            }
            record(monitor.process(sample(s)))
        }
        while index < actions.count {
            apply(actions[index])
            index += 1
        }
        result.finalState = monitor.state.kindName
        result.finalBaseline = monitor.baseline
        return result
    }
}

// MARK: - Tests

final class FixtureReplayTests: XCTestCase {
    static let fixtureNames = [
        "steady_neutral",
        "gradual_forward_slouch",
        "brief_glances_down",
        "lateral_right_tilt",
        "cooldown_retrigger",
        "calibration_too_much_movement",
        "disconnect_mid_tilt",
        "looking_up_backward",
        "nod_axis_calibration_yawed_earbud",
        "nod_axis_calibration_up",
        "nod_axis_calibration_sideways_rejected",
        "nod_axis_calibration_no_nod",
        "calibration_brief_fidget",
        "calibration_slow_slouch",
    ]

    func testFixtureDirectoryContainsAllFixtures() throws {
        let dir = try XCTUnwrap(FixtureReplay.fixtureDirectory(), "shared/fixtures/motion not found from #filePath")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".json") }
        XCTAssertEqual(Set(files.map { String($0.dropLast(5)) }), Set(FixtureReplayTests.fixtureNames))
    }

    /// Fixtures state their axes explicitly; they must equal AlignCore's default (D-011).
    func testFixtureAxesMatchAlignCoreDefault() throws {
        for name in FixtureReplayTests.fixtureNames {
            let fixture = try FixtureReplay.load(name)
            let axes = fixture.config?.configuration().axes
            XCTAssertEqual(axes, HeadAxisConvention.airPodsDefault, name)
        }
    }

    func testSteadyNeutral() throws { try check("steady_neutral") }
    func testGradualForwardSlouch() throws { try check("gradual_forward_slouch") }
    func testBriefGlancesDown() throws { try check("brief_glances_down") }
    func testLateralRightTilt() throws { try check("lateral_right_tilt") }
    func testCooldownRetrigger() throws { try check("cooldown_retrigger") }
    func testCalibrationTooMuchMovement() throws { try check("calibration_too_much_movement") }
    func testDisconnectMidTilt() throws { try check("disconnect_mid_tilt") }
    func testLookingUpBackward() throws { try check("looking_up_backward") }
    func testNodAxisCalibrationYawedEarbud() throws { try check("nod_axis_calibration_yawed_earbud") }
    func testNodAxisCalibrationUp() throws { try check("nod_axis_calibration_up") }
    func testNodAxisCalibrationSidewaysRejected() throws { try check("nod_axis_calibration_sideways_rejected") }
    func testNodAxisCalibrationNoNod() throws { try check("nod_axis_calibration_no_nod") }
    func testCalibrationBriefFidget() throws { try check("calibration_brief_fidget") }
    func testCalibrationSlowSlouch() throws { try check("calibration_slow_slouch") }

    /// The slow-slouch fixture is about D-020: only the drift rule rejects it.
    func testSlowSlouchFixtureIsRejectedByTheDriftRule() throws {
        let fixture = try FixtureReplay.load("calibration_slow_slouch")
        var noDrift = fixture.config?.configuration() ?? .default
        noDrift.calibrationMaxDriftDegrees = 180
        XCTAssertEqual(FixtureReplay.replay(fixture, configuration: noDrift).calibrationOutcomes, ["succeeded"])
    }

    /// The fidget fixture is about D-017 (b): the v1 rule (quantile 1.0) rejects it.
    func testBriefFidgetFixtureFailsTheV1Rule() throws {
        let fixture = try FixtureReplay.load("calibration_brief_fidget")
        var v1 = fixture.config?.configuration() ?? .default
        v1.calibrationSpreadQuantile = 1
        XCTAssertEqual(FixtureReplay.replay(fixture, configuration: v1).calibrationOutcomes, ["tooMuchMovement"])
    }

    private func check(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let fixture = try FixtureReplay.load(name)
        XCTAssertEqual(fixture.schemaVersion, 1, file: file, line: line)
        XCTAssertEqual(fixture.name, name, file: file, line: line)
        let result = FixtureReplay.replay(fixture)
        assertExpected(fixture, result, file: file, line: line)
        assertReference(fixture, result, file: file, line: line)
    }

    /// Semantic expectations derived from the scripted truth, with time tolerance.
    private func assertExpected(_ fixture: MotionFixture, _ result: ReplayResult, file: StaticString, line: UInt) {
        let exp = fixture.expected
        let tol = exp.tolerances.timeSeconds
        let n = fixture.name
        XCTAssertEqual(result.calibrationOutcomes, exp.calibrationOutcomes, "\(n): calibration outcomes", file: file, line: line)
        XCTAssertEqual(result.finalState, exp.finalState, "\(n): final state", file: file, line: line)
        XCTAssertEqual(result.reminders.count, exp.reminders.count, "\(n): reminder count", file: file, line: line)
        for (got, want) in zip(result.reminders, exp.reminders) {
            XCTAssertEqual(got.direction.rawValue, want.direction, "\(n): reminder direction", file: file, line: line)
            XCTAssertEqual(got.timestamp, want.t, accuracy: tol, "\(n): reminder time", file: file, line: line)
        }
        XCTAssertEqual(result.episodes.count, exp.episodes.count, "\(n): episode count", file: file, line: line)
        for (got, want) in zip(result.episodes, exp.episodes) {
            XCTAssertEqual(got.direction.rawValue, want.direction, "\(n): episode direction", file: file, line: line)
            XCTAssertEqual(got.startTimestamp, want.start, accuracy: tol, "\(n): episode start", file: file, line: line)
            XCTAssertEqual(got.endTimestamp, want.end, accuracy: tol, "\(n): episode end", file: file, line: line)
            XCTAssertEqual(got.reminderTriggered, want.reminderTriggered, "\(n): episode reminderTriggered", file: file, line: line)
        }
        if let want = exp.axisCalibrationOutcomes {
            XCTAssertEqual(result.axisCalibrationOutcomes, want, "\(n): axis calibration outcomes", file: file, line: line)
        }
        if let want = exp.learnedAxes {
            let yaw = result.learnedYawDegrees
            XCTAssertEqual(yaw != nil, want.present, "\(n): learned axes present", file: file, line: line)
            if let yaw = yaw, let wantYaw = want.yawDegrees {
                XCTAssertEqual(yaw, wantYaw, accuracy: want.toleranceDegrees ?? 2, "\(n): learned yaw", file: file, line: line)
            }
        }
        if let bound = exp.maxAbsLateral {
            let got = result.maxAbsLateralDegrees(from: bound.from, to: bound.to)
            XCTAssertLessThanOrEqual(got, bound.degrees, "\(n): max |lateral| in [\(bound.from), \(bound.to)]", file: file, line: line)
        }
    }

    /// Cross-language parity with the reference output stored in the fixture.
    private func assertReference(_ fixture: MotionFixture, _ result: ReplayResult, file: StaticString, line: UInt) {
        let ref = fixture.reference
        let n = fixture.name
        let timeTol = 1.0 / fixture.sampleRateHz + 1e-6
        let degreeTol = 0.05
        XCTAssertEqual(result.calibrationOutcomes, ref.calibrationOutcomes, "\(n): parity calibration outcomes", file: file, line: line)
        XCTAssertEqual(result.axisCalibrationOutcomes, ref.axisCalibrationOutcomes ?? [], "\(n): parity axis calibration outcomes", file: file, line: line)
        if ref.axisCalibrationOutcomes != nil {
            let want = ref.learnedAxes?.convention
            XCTAssertEqual(result.learnedAxes == nil, want == nil, "\(n): parity learned axes present", file: file, line: line)
            if let got = result.learnedAxes, let want = want {
                for (g, w) in [(got.forwardAxis, want.forwardAxis), (got.lateralAxis, want.lateralAxis)] {
                    XCTAssertEqual(g.x, w.x, accuracy: 1e-4, "\(n): parity learned axes", file: file, line: line)
                    XCTAssertEqual(g.y, w.y, accuracy: 1e-4, "\(n): parity learned axes", file: file, line: line)
                    XCTAssertEqual(g.z, w.z, accuracy: 1e-4, "\(n): parity learned axes", file: file, line: line)
                }
            }
        }
        XCTAssertEqual(result.finalState, ref.finalState, "\(n): parity final state", file: file, line: line)
        XCTAssertEqual(result.stateTransitions, ref.stateTransitions, "\(n): parity state transitions", file: file, line: line)
        XCTAssertEqual(result.reminders.count, ref.reminders.count, "\(n): parity reminder count", file: file, line: line)
        for (got, want) in zip(result.reminders, ref.reminders) {
            XCTAssertEqual(got.direction.rawValue, want.direction, "\(n): parity reminder direction", file: file, line: line)
            XCTAssertEqual(got.timestamp, want.t, accuracy: timeTol, "\(n): parity reminder time", file: file, line: line)
            XCTAssertEqual(got.deviationDegrees, want.deviationDegrees, accuracy: degreeTol, "\(n): parity deviation", file: file, line: line)
            XCTAssertEqual(got.sustainedSeconds, want.sustainedSeconds, accuracy: timeTol, "\(n): parity sustained seconds", file: file, line: line)
        }
        XCTAssertEqual(result.episodes.count, ref.episodes.count, "\(n): parity episode count", file: file, line: line)
        for (got, want) in zip(result.episodes, ref.episodes) {
            XCTAssertEqual(got.direction.rawValue, want.direction, "\(n): parity episode direction", file: file, line: line)
            XCTAssertEqual(got.startTimestamp, want.start, accuracy: timeTol, "\(n): parity episode start", file: file, line: line)
            XCTAssertEqual(got.endTimestamp, want.end, accuracy: timeTol, "\(n): parity episode end", file: file, line: line)
            XCTAssertEqual(got.peakDeviationDegrees, want.peakDeviationDegrees, accuracy: degreeTol, "\(n): parity peak", file: file, line: line)
            XCTAssertEqual(got.reminderTriggered, want.reminderTriggered, "\(n): parity reminderTriggered", file: file, line: line)
        }
    }
}
