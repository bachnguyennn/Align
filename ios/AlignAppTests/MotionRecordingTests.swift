import XCTest
import SwiftData
import AlignCore
@testable import Align

/// The recording JSON format (shared/fixtures/README.md, "Recordings") and the recorder's file
/// lifecycle (D-017 (d)).
final class MotionRecordingEncoderTests: XCTestCase {
    /// Configuration keys documented in shared/fixtures/README.md (`config`).
    private let documentedConfigKeys: Set<String> = [
        "calibrationDuration", "calibrationMaxSpreadDegrees", "minimumCalibrationSamples",
        "forwardThresholdDegrees", "backwardThresholdDegrees", "lateralThresholdDegrees",
        "hysteresisDegrees", "sustainedDuration", "reminderCooldown", "smoothingTimeConstant",
        "maxProcessingRateHz", "maxSampleGap", "forwardAxis", "lateralAxis",
        "calibrationSpreadQuantile", "axisCalibrationDuration", "axisCalibrationMinimumNodDegrees",
        "axisCalibrationMaxYawDegrees", "axisCalibrationMaxOffAxisRatio",
    ]

    private func makeRecording(notes: String, baseline: NeutralBaseline?, sampleCount: Int = 3) -> MotionRecording {
        let samples = (0..<sampleCount).map { i in
            MotionSample(
                timestamp: 1234.56 + Double(i) * 0.04,
                attitude: Quaternion(x: -0.076, y: -0.0221, z: -0.0465, w: 0.9958),
                gravity: Vector3(x: -0.05198, y: 0.15071, z: -0.98721),
                rotationRate: i == 0 ? Vector3(x: 0.01, y: -0.02, z: 0.03) : nil,
                userAcceleration: Vector3(x: 0.1, y: 0.2, z: 0.3),
                sensorLocation: .headphoneLeft
            )
        }
        var configuration = PostureConfiguration.default
        configuration.forwardThresholdDegrees = 12
        return MotionRecording(
            name: "2026-11-02-recording-140300",
            metadata: RecordingMetadata(
                appVersion: "0.1.0 (1)",
                device: "iPhone16,1",
                headphones: "unknown",
                notes: notes,
                createdAt: Date(timeIntervalSince1970: 1_793_628_180)
            ),
            configuration: configuration,
            baseline: baseline,
            actions: [
                RecordedAction(t: 1234.561, type: .beginCalibration),
                RecordedAction(t: 1234.601, type: .beginAxisCalibration),
            ],
            samples: samples
        )
    }

    private func decode(_ data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    func testEncodesTheDocumentedRecordingFormat() throws {
        let learned = HeadAxisConvention(forwardAxis: Vector3(x: -0.9, y: 0.43589, z: 0), lateralAxis: Vector3(x: 0.43589, y: 0.9, z: 0))
        let baseline = NeutralBaseline(gravity: Vector3(x: 0.05, y: 0.14, z: -0.99), capturedAt: Date(), sampleCount: 251, version: 3, learnedAxes: learned)
        let notes = "slouching at desk, \"laptop\"\nsecond line \\ ok"
        let json = try decode(MotionRecordingEncoder.encode(makeRecording(notes: notes, baseline: baseline)))

        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        XCTAssertEqual(json["name"] as? String, "2026-11-02-recording-140300")
        for forbidden in ["expected", "reference", "truth", "generator"] {
            XCTAssertNil(json[forbidden], "\(forbidden) must not appear in a recording")
        }
        for key in ["recording", "sampleRateHz", "startTimestamp", "config", "baseline", "actions", "samples"] {
            XCTAssertNotNil(json[key], "missing \(key)")
        }

        let recording = try XCTUnwrap(json["recording"] as? [String: Any])
        XCTAssertEqual(recording["appVersion"] as? String, "0.1.0 (1)")
        XCTAssertEqual(recording["device"] as? String, "iPhone16,1")
        XCTAssertEqual(recording["headphones"] as? String, "unknown")
        XCTAssertEqual(recording["notes"] as? String, notes, "notes are escaped and round-trip")
        let createdAt = try XCTUnwrap(recording["createdAt"] as? String)
        XCTAssertTrue(createdAt.hasSuffix("Z"))
        XCTAssertEqual(ISO8601DateFormatter().date(from: createdAt), Date(timeIntervalSince1970: 1_793_628_180))

        XCTAssertEqual(try XCTUnwrap(json["sampleRateHz"] as? Double), 25, accuracy: 0.05)
        XCTAssertEqual(try XCTUnwrap(json["startTimestamp"] as? Double), 1234.56, accuracy: 1e-9)

        let config = try XCTUnwrap(json["config"] as? [String: Any])
        XCTAssertTrue(Set(config.keys).isSubset(of: documentedConfigKeys), "unknown keys: \(Set(config.keys).subtracting(documentedConfigKeys))")
        XCTAssertEqual(config["forwardThresholdDegrees"] as? Double, 12)
        XCTAssertEqual(config["forwardAxis"] as? [Double], [-1, 0, 0])
        XCTAssertEqual(config["lateralAxis"] as? [Double], [0, 1, 0])
        XCTAssertEqual(config["minimumCalibrationSamples"] as? Int, 100)
        XCTAssertTrue(config["maxProcessingRateHz"] is NSNull)

        let storedBaseline = try XCTUnwrap(json["baseline"] as? [String: Any])
        XCTAssertEqual(storedBaseline["gravity"] as? [Double], [0.05, 0.14, -0.99])
        XCTAssertEqual(storedBaseline["version"] as? Int, 3)
        XCTAssertEqual(storedBaseline["sampleCount"] as? Int, 251)
        let learnedAxes = try XCTUnwrap(storedBaseline["learnedAxes"] as? [String: Any])
        XCTAssertEqual(learnedAxes["forwardAxis"] as? [Double], [-0.9, 0.43589, 0])
        XCTAssertEqual(learnedAxes["lateralAxis"] as? [Double], [0.43589, 0.9, 0])

        let actions = try XCTUnwrap(json["actions"] as? [[String: Any]])
        XCTAssertEqual(actions.compactMap { $0["type"] as? String }, ["beginCalibration", "beginAxisCalibration"])
        XCTAssertEqual(try XCTUnwrap(actions.first?["t"] as? Double), 1234.561, accuracy: 1e-9)

        let samples = try XCTUnwrap(json["samples"] as? [[String: Any]])
        XCTAssertEqual(samples.count, 3)
        let first = try XCTUnwrap(samples.first)
        XCTAssertEqual(try XCTUnwrap(first["t"] as? Double), 1234.56, accuracy: 1e-9)
        XCTAssertEqual(first["q"] as? [Double], [-0.076, -0.0221, -0.0465, 0.9958])
        XCTAssertEqual(first["g"] as? [Double], [-0.05198, 0.15071, -0.98721])
        XCTAssertEqual(first["r"] as? [Double], [0.01, -0.02, 0.03])
        XCTAssertNil(samples[1]["r"])
        for sample in samples {
            XCTAssertEqual(Set(sample.keys).subtracting(["t", "q", "g", "r"]), [], "only documented sample keys")
        }
    }

    func testOmitsEmptyNotesAndWritesNullBaseline() throws {
        let json = try decode(MotionRecordingEncoder.encode(makeRecording(notes: "   ", baseline: nil)))
        let recording = try XCTUnwrap(json["recording"] as? [String: Any])
        XCTAssertNil(recording["notes"])
        XCTAssertTrue(json["baseline"] is NSNull)
        XCTAssertNil((json["baseline"] as? [String: Any])?["learnedAxes"])
    }

    func testEmptyRecordingIsStillValidJSON() throws {
        let json = try decode(MotionRecordingEncoder.encode(makeRecording(notes: "", baseline: nil, sampleCount: 0)))
        XCTAssertEqual((json["samples"] as? [Any])?.count, 0)
    }

    func testNumberFormatting() {
        XCTAssertEqual(MotionRecordingEncoder.number(0.15000, decimals: 5), "0.15")
        XCTAssertEqual(MotionRecordingEncoder.number(1, decimals: 4), "1")
        XCTAssertEqual(MotionRecordingEncoder.number(-0.000001, decimals: 4), "0")
        XCTAssertEqual(MotionRecordingEncoder.number(-0.051981, decimals: 5), "-0.05198")
        XCTAssertEqual(MotionRecordingEncoder.number(.nan, decimals: 3), "null")
        XCTAssertEqual(MotionRecordingEncoder.string("a\"b\\c\n\u{1}"), "\"a\\\"b\\\\c\\n\\u0001\"")
    }
}

final class MotionRecorderTests: XCTestCase {
    @MainActor
    private func decodeFile(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @MainActor
    func testRecordsSamplesBaselineAndActionsThenDeletesTheFile() throws {
        let h = ControllerHarness()
        defer { h.finish() }
        h.connect()
        h.calibrateNeutral()
        XCTAssertTrue(h.controller.canStartRecording)

        h.controller.startRecording(length: .thirtySeconds, notes: "sitting upright")
        XCTAssertTrue(h.controller.recorder.isRecording)
        h.feed(seconds: 1)
        h.controller.startAxisCalibration(client: .diagnostics)
        h.nod()
        h.controller.stopRecording()

        let file = try XCTUnwrap(h.controller.recorder.finishedRecording)
        XCTAssertEqual(file.stopReason, .stoppedByUser)
        XCTAssertEqual(file.sampleCount, 125)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path))
        XCTAssertTrue(file.url.path.hasPrefix(h.recordingDirectory.path), "written to the recordings folder")

        let json = try decodeFile(file.url)
        XCTAssertEqual((json["samples"] as? [Any])?.count, 125)
        XCTAssertEqual(json["name"] as? String, file.url.deletingPathExtension().lastPathComponent)
        let recording = try XCTUnwrap(json["recording"] as? [String: Any])
        XCTAssertEqual(recording["notes"] as? String, "sitting upright")
        XCTAssertNotNil(recording["device"] as? String)
        XCTAssertNotNil(recording["appVersion"] as? String)
        XCTAssertNotNil(recording["headphones"] as? String)
        let baseline = try XCTUnwrap(json["baseline"] as? [String: Any])
        XCTAssertEqual(baseline["version"] as? Int, 1, "the baseline at the start of the recording")
        let types = (json["actions"] as? [[String: Any]])?.compactMap { $0["type"] as? String } ?? []
        XCTAssertTrue(types.contains("beginAxisCalibration"))
        // Every action is stamped just after a recorded sample, so replay applies it in place.
        let sampleTimes = (json["samples"] as? [[String: Any]])?.compactMap { $0["t"] as? Double } ?? []
        for action in (json["actions"] as? [[String: Any]]) ?? [] {
            let t = try XCTUnwrap(action["t"] as? Double)
            let previous = try XCTUnwrap(sampleTimes.last { $0 < t })
            XCTAssertEqual(t - previous, MotionRecorder.actionOffset, accuracy: 1e-5)
        }

        // Nothing went into SwiftData.
        let context = h.environment.modelContainer.mainContext
        XCTAssertEqual(try context.fetch(FetchDescriptor<MonitoringSession>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PostureEvent>()).count, 0)

        // A new recording deletes the previous file; leaving the screen deletes the new one.
        h.controller.startRecording(length: .oneMinute, notes: "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path))
        h.feed(seconds: 0.5)
        h.controller.stopRecording()
        let second = try XCTUnwrap(h.controller.recorder.finishedRecording)
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.url.path))
        h.controller.discardRecording()
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.recordingDirectory.path))
        XCTAssertEqual(h.controller.recorder.state, .idle)
    }

    @MainActor
    func testStopsAtTheChosenLength() throws {
        let h = ControllerHarness()
        defer { h.finish() }
        h.connect()
        h.controller.startRecording(length: .thirtySeconds, notes: "")
        h.feed(seconds: 31)
        let file = try XCTUnwrap(h.controller.recorder.finishedRecording)
        XCTAssertEqual(file.stopReason, .completed)
        XCTAssertEqual(Double(file.sampleCount), 750, accuracy: 2)
        XCTAssertFalse(h.controller.recorder.isRecording)
    }

    @MainActor
    func testStopsOnDisconnectAndKeepsWhatWasRecorded() throws {
        let h = ControllerHarness()
        defer { h.finish() }
        h.connect()
        h.controller.startRecording(length: .twoMinutes, notes: "")
        h.feed(seconds: 2)
        h.controller.handle(.connectionChanged(.waitingForHeadphones))
        let file = try XCTUnwrap(h.controller.recorder.finishedRecording)
        XCTAssertEqual(file.stopReason, .disconnected)
        XCTAssertEqual(file.sampleCount, 50)
        XCTAssertFalse(h.controller.canStartRecording)
    }

    @MainActor
    func testStopsWhenTheAppGoesToTheBackground() throws {
        let h = ControllerHarness()
        defer { h.finish() }
        h.connect()
        h.controller.startRecording(length: .twoMinutes, notes: "")
        h.feed(seconds: 1)
        h.controller.appDidLeaveForeground(stopSensor: false)
        XCTAssertTrue(h.controller.recorder.isRecording, "inactive (e.g. Control Center) keeps recording")
        h.controller.appDidLeaveForeground(stopSensor: true)
        let file = try XCTUnwrap(h.controller.recorder.finishedRecording)
        XCTAssertEqual(file.stopReason, .appBackgrounded)
    }

    @MainActor
    func testNeedsAConnectedStream() {
        let h = ControllerHarness()
        defer { h.finish() }
        h.controller.startRecording(length: .thirtySeconds, notes: "")
        XCTAssertFalse(h.controller.recorder.isRecording)
        h.controller.acquireSensor(.diagnostics)
        h.controller.startRecording(length: .thirtySeconds, notes: "")
        XCTAssertFalse(h.controller.recorder.isRecording, "not connected yet")
    }

    @MainActor
    func testRecordingWithoutSamplesFailsWithoutAFile() {
        let h = ControllerHarness()
        defer { h.finish() }
        h.connect()
        h.controller.startRecording(length: .thirtySeconds, notes: "")
        h.controller.stopRecording()
        guard case .failed = h.controller.recorder.state else {
            return XCTFail("expected a failure, got \(h.controller.recorder.state)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.recordingDirectory.path))
    }

    @MainActor
    func testRemoveFilesDeletesLeftovers() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("align-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("left-over.json", isDirectory: false)
        try Data("{}".utf8).write(to: file)
        MotionRecorder.removeFiles(in: directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }
}
