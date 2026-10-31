import Foundation
import Observation
import AlignCore

// Opt-in diagnostic motion recording (D-017 (d)). A narrow, user-initiated exception to D-007:
// raw samples are kept in memory only while a recording runs, written to one temporary file in
// the recording JSON format (shared/fixtures/README.md, "Recordings") so the user can share it,
// and deleted when they leave Diagnostics, start a new recording, or relaunch the app.
// Nothing here touches SwiftData, UserDefaults or the network.

/// Monitor calls recorded in `actions`; raw values are the fixture action types.
enum RecordedActionType: String, CaseIterable {
    case beginCalibration
    case cancelCalibration
    case beginAxisCalibration
    case cancelAxisCalibration
    case clearLearnedAxes
    case resetCooldown
    case interrupt
}

struct RecordedAction: Equatable {
    /// Replay applies an action before the first sample whose `t` ≥ this, so it is stamped just
    /// after the last sample the app had processed (see `MotionRecorder.actionOffset`).
    var t: TimeInterval
    var type: RecordedActionType
}

/// The `recording` block.
struct RecordingMetadata: Equatable {
    /// CFBundleShortVersionString (CFBundleVersion).
    var appVersion: String
    /// Hardware model identifier, never the user-assigned device name.
    var device: String
    /// Only what the API exposes: Core Motion does not name the headphone model, so "unknown"
    /// for AirPods (the audio route's port name is user-assigned and is deliberately not used).
    var headphones: String
    /// Free text typed by the user; omitted from the file when empty.
    var notes: String
    var createdAt: Date
}

/// Everything that goes into one recording file.
struct MotionRecording {
    var name: String
    var metadata: RecordingMetadata
    /// The configuration in use when the recording started.
    var configuration: PostureConfiguration
    /// The baseline in use when the recording started (with `learnedAxes`, if any).
    var baseline: NeutralBaseline?
    var actions: [RecordedAction]
    var samples: [MotionSample]
}

/// Writes the recording JSON format by hand, so numbers are rounded as documented (q 4 decimals,
/// g 5) and keys keep the documented order. Pure; unit-tested by decoding the output back.
enum MotionRecordingEncoder {
    static let schemaVersion = 1

    /// `config` keys written, in order: the documented fixture configuration keys (Swift property
    /// names) plus `forwardAxis` / `lateralAxis`. The D-020 drift fields are left out because the
    /// replay tool rejects keys it does not know yet; replay then uses their defaults.
    static let configKeys: [String] = [
        "calibrationDuration", "calibrationMaxSpreadDegrees", "calibrationSpreadQuantile",
        "calibrationMaxDriftDegrees", "calibrationDriftWindow", "minimumCalibrationSamples", "forwardThresholdDegrees", "backwardThresholdDegrees",
        "lateralThresholdDegrees", "hysteresisDegrees", "sustainedDuration", "reminderCooldown",
        "smoothingTimeConstant", "maxProcessingRateHz", "maxSampleGap", "forwardAxis", "lateralAxis",
        "axisCalibrationDuration", "axisCalibrationMinimumNodDegrees", "axisCalibrationMaxYawDegrees",
        "axisCalibrationMaxOffAxisRatio",
    ]

    static func encode(_ recording: MotionRecording) -> Data {
        let samples = recording.samples.filter(isEncodable)
        var lines: [String] = ["{"]
        lines.append("  \"schemaVersion\": \(schemaVersion),")
        lines.append("  \"name\": \(string(recording.name)),")
        lines.append("  \"recording\": \(metadata(recording.metadata)),")
        lines.append("  \"sampleRateHz\": \(number(nominalRate(samples), decimals: 1)),")
        lines.append("  \"startTimestamp\": \(number(samples.first?.timestamp ?? 0, decimals: 6)),")
        lines.append("  \"config\": \(config(recording.configuration)),")
        lines.append("  \"baseline\": \(baseline(recording.baseline)),")
        let actions = recording.actions
            .filter { $0.t.isFinite }
            .map { "{ \"t\": \(number($0.t, decimals: 6)), \"type\": \(string($0.type.rawValue)) }" }
        lines.append("  \"actions\": [" + actions.joined(separator: ", ") + "],")
        if samples.isEmpty {
            lines.append("  \"samples\": []")
        } else {
            lines.append("  \"samples\": [")
            for (index, sample) in samples.enumerated() {
                let separator = index == samples.count - 1 ? "" : ","
                lines.append("    " + encodeSample(sample) + separator)
            }
            lines.append("  ]")
        }
        lines.append("}")
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    /// File name without `.json`, e.g. "2026-11-02-recording-140300" (UTC).
    static func name(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd-'recording'-HHmmss"
        return formatter.string(from: date)
    }

    /// ISO 8601 in UTC, e.g. "2026-11-02T14:03:00Z".
    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// Mean delivered rate, rounded to 0.1 Hz (25 if it cannot be measured). Nominal only:
    /// timestamps are authoritative.
    static func nominalRate(_ samples: [MotionSample]) -> Double {
        guard samples.count >= 2, let first = samples.first, let last = samples.last else { return 25 }
        let span = last.timestamp - first.timestamp
        guard span > 0 else { return 25 }
        return (Double(samples.count - 1) / span * 10).rounded() / 10
    }

    // MARK: Parts

    private static func metadata(_ m: RecordingMetadata) -> String {
        var fields = [
            "\"appVersion\": \(string(m.appVersion))",
            "\"device\": \(string(m.device))",
            "\"headphones\": \(string(m.headphones))",
        ]
        let notes = m.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            fields.append("\"notes\": \(string(notes))")
        }
        fields.append("\"createdAt\": \(string(timestamp(m.createdAt)))")
        return "{ " + fields.joined(separator: ", ") + " }"
    }

    private static func config(_ c: PostureConfiguration) -> String {
        var values: [String: String] = [
            "calibrationDuration": number(c.calibrationDuration, decimals: 6),
            "calibrationMaxSpreadDegrees": number(c.calibrationMaxSpreadDegrees, decimals: 6),
            "calibrationSpreadQuantile": number(c.calibrationSpreadQuantile, decimals: 6),
            "calibrationMaxDriftDegrees": number(c.calibrationMaxDriftDegrees, decimals: 6),
            "calibrationDriftWindow": number(c.calibrationDriftWindow, decimals: 6),
            "minimumCalibrationSamples": String(c.minimumCalibrationSamples),
            "forwardThresholdDegrees": number(c.forwardThresholdDegrees, decimals: 6),
            "backwardThresholdDegrees": number(c.backwardThresholdDegrees, decimals: 6),
            "lateralThresholdDegrees": number(c.lateralThresholdDegrees, decimals: 6),
            "hysteresisDegrees": number(c.hysteresisDegrees, decimals: 6),
            "sustainedDuration": number(c.sustainedDuration, decimals: 6),
            "reminderCooldown": number(c.reminderCooldown, decimals: 6),
            "smoothingTimeConstant": number(c.smoothingTimeConstant, decimals: 6),
            "maxSampleGap": number(c.maxSampleGap, decimals: 6),
            "forwardAxis": vector(c.axes.forwardAxis, decimals: 6),
            "lateralAxis": vector(c.axes.lateralAxis, decimals: 6),
            "axisCalibrationDuration": number(c.axisCalibrationDuration, decimals: 6),
            "axisCalibrationMinimumNodDegrees": number(c.axisCalibrationMinimumNodDegrees, decimals: 6),
            "axisCalibrationMaxYawDegrees": number(c.axisCalibrationMaxYawDegrees, decimals: 6),
            "axisCalibrationMaxOffAxisRatio": number(c.axisCalibrationMaxOffAxisRatio, decimals: 6),
        ]
        values["maxProcessingRateHz"] = c.maxProcessingRateHz.map { number($0, decimals: 6) } ?? "null"
        let fields = configKeys.compactMap { key in
            values[key].map { "\(string(key)): \($0)" }
        }
        return "{ " + fields.joined(separator: ", ") + " }"
    }

    private static func baseline(_ b: NeutralBaseline?) -> String {
        guard let b else { return "null" }
        var fields = [
            "\"gravity\": \(vector(b.gravity, decimals: 6))",
            "\"version\": \(b.version)",
            "\"sampleCount\": \(b.sampleCount)",
        ]
        if let axes = b.learnedAxes {
            fields.append(
                "\"learnedAxes\": { \"forwardAxis\": \(vector(axes.forwardAxis, decimals: 6)), "
                    + "\"lateralAxis\": \(vector(axes.lateralAxis, decimals: 6)) }"
            )
        }
        return "{ " + fields.joined(separator: ", ") + " }"
    }

    private static func encodeSample(_ s: MotionSample) -> String {
        let q = s.attitude
        let quaternion: [String] = [q.x, q.y, q.z, q.w].map { number($0, decimals: 4) }
        var text = "{\"t\":" + number(s.timestamp, decimals: 6)
        text += ",\"q\":[" + quaternion.joined(separator: ",") + "]"
        if let g = s.gravity, isFinite(g) {
            text += ",\"g\":" + compactVector(g, decimals: 5)
        }
        if let r = s.rotationRate, isFinite(r) {
            text += ",\"r\":" + compactVector(r, decimals: 4)
        }
        return text + "}"
    }

    private static func isEncodable(_ s: MotionSample) -> Bool {
        let q = s.attitude
        return s.timestamp.isFinite && q.x.isFinite && q.y.isFinite && q.z.isFinite && q.w.isFinite
    }

    private static func isFinite(_ v: Vector3) -> Bool {
        v.x.isFinite && v.y.isFinite && v.z.isFinite
    }

    private static func vector(_ v: Vector3, decimals: Int) -> String {
        "[" + [v.x, v.y, v.z].map { number($0, decimals: decimals) }.joined(separator: ", ") + "]"
    }

    private static func compactVector(_ v: Vector3, decimals: Int) -> String {
        "[" + [v.x, v.y, v.z].map { number($0, decimals: decimals) }.joined(separator: ",") + "]"
    }

    // MARK: JSON primitives

    /// Fixed-point with trailing zeros trimmed ("0.15", "1", "-0.05198"); `null` if not finite.
    static func number(_ value: Double, decimals: Int) -> String {
        guard value.isFinite else { return "null" }
        var text = String(format: "%.\(decimals)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") {
                text.removeLast()
            }
            if text.hasSuffix(".") {
                text.removeLast()
            }
        }
        if text == "-0" {
            text = "0"
        }
        return text
    }

    /// A JSON string literal with quotes, backslashes and control characters escaped.
    static func string(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"":
                out += "\\\""
            case "\\":
                out += "\\\\"
            case "\n":
                out += "\\n"
            case "\r":
                out += "\\r"
            case "\t":
                out += "\\t"
            default:
                if scalar.value < 0x20 || scalar.value == 0x2028 || scalar.value == 0x2029 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }
}

// MARK: - Recorder

enum RecordingLength: Int, CaseIterable, Identifiable {
    case thirtySeconds = 30
    case oneMinute = 60
    case twoMinutes = 120

    var id: Int { rawValue }

    var seconds: TimeInterval { TimeInterval(rawValue) }

    var title: String {
        switch self {
        case .thirtySeconds: return "30 s"
        case .oneMinute: return "1 min"
        case .twoMinutes: return "2 min"
        }
    }

    var spokenTitle: String {
        switch self {
        case .thirtySeconds: return "30 seconds"
        case .oneMinute: return "1 minute"
        case .twoMinutes: return "2 minutes"
        }
    }
}

enum RecordingStopReason: Equatable {
    case completed
    case stoppedByUser
    case disconnected
    case appBackgrounded
    case sensorStopped

    /// Shown next to a finished recording; nil when it ran its full length.
    var message: String? {
        switch self {
        case .completed:
            return nil
        case .stoppedByUser:
            return "You stopped the recording early."
        case .disconnected:
            return "The recording stopped early because the AirPods disconnected."
        case .appBackgrounded:
            return "The recording stopped early because you left Align."
        case .sensorStopped:
            return "The recording stopped early because the motion sensor stopped."
        }
    }
}

struct FinishedRecording: Equatable {
    var url: URL
    var sampleCount: Int
    /// Time between the first and the last sample.
    var durationSeconds: TimeInterval
    var stopReason: RecordingStopReason
}

/// Collects samples and actions for one recording, then writes the file. Main actor only.
/// `MonitoringController` feeds it; Diagnostics shows its `state`.
@MainActor
@Observable
final class MotionRecorder {
    enum State: Equatable {
        case idle
        case recording(length: RecordingLength, elapsed: TimeInterval, sampleCount: Int)
        case finished(FinishedRecording)
        case failed(String)
    }

    /// Actions are stamped this long after the last recorded sample: earlier than any next
    /// sample (headphone motion arrives at about 25 Hz), so replay applies them at the same point.
    static let actionOffset: TimeInterval = 0.001

    private(set) var state: State = .idle

    private let directory: URL
    private let clock: () -> TimeInterval
    @ObservationIgnored private var active: ActiveRecording?
    @ObservationIgnored private var samples: [MotionSample] = []
    @ObservationIgnored private var actions: [RecordedAction] = []
    @ObservationIgnored private var deadline: Task<Void, Never>?

    private struct ActiveRecording {
        var length: RecordingLength
        var startedAt: TimeInterval
        var metadata: RecordingMetadata
        var configuration: PostureConfiguration
        var baseline: NeutralBaseline?
    }

    /// The temporary folder that holds at most one recording file; removed as a whole on cleanup.
    nonisolated static var defaultDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("AlignMotionRecordings", isDirectory: true)
    }

    /// - Parameters:
    ///   - directory: where the file is written; `defaultDirectory` when nil.
    ///   - clock: monotonic seconds for the recording length; `systemUptime` when nil.
    init(directory: URL? = nil, clock: (() -> TimeInterval)? = nil) {
        self.directory = directory ?? MotionRecorder.defaultDirectory
        if let clock {
            self.clock = clock
        } else {
            self.clock = { ProcessInfo.processInfo.systemUptime }
        }
    }

    var isRecording: Bool { active != nil }

    var finishedRecording: FinishedRecording? {
        if case .finished(let recording) = state {
            return recording
        }
        return nil
    }

    /// Starts a new recording, deleting any earlier file first.
    func start(
        length: RecordingLength,
        metadata: RecordingMetadata,
        configuration: PostureConfiguration,
        baseline: NeutralBaseline?
    ) {
        discard()
        active = ActiveRecording(
            length: length,
            startedAt: clock(),
            metadata: metadata,
            configuration: configuration,
            baseline: baseline
        )
        state = .recording(length: length, elapsed: 0, sampleCount: 0)
        scheduleDeadline(after: length.seconds)
    }

    func append(_ sample: MotionSample) {
        guard let current = active else { return }
        // Generous cap (200 Hz) so a misbehaving source cannot grow memory without bound.
        if samples.count < Int(current.length.seconds * 200) + 200 {
            samples.append(sample)
        }
        let elapsed = clock() - current.startedAt
        if elapsed >= current.length.seconds {
            stop(.completed)
        } else {
            state = .recording(length: current.length, elapsed: max(0, elapsed), sampleCount: samples.count)
        }
    }

    func record(_ type: RecordedActionType) {
        guard active != nil else { return }
        let base = samples.last?.timestamp ?? clock()
        actions.append(RecordedAction(t: base + MotionRecorder.actionOffset, type: type))
    }

    /// Ends the recording and writes the file (if any sample arrived). No-op when not recording.
    func stop(_ reason: RecordingStopReason) {
        guard let current = active else { return }
        active = nil
        deadline?.cancel()
        deadline = nil
        let recordedSamples = samples
        let recordedActions = actions
        samples = []
        actions = []

        guard let first = recordedSamples.first, let last = recordedSamples.last else {
            state = .failed("No motion data arrived, so there is nothing to share. Check that your AirPods are connected, then try again.")
            return
        }
        let recording = MotionRecording(
            name: MotionRecordingEncoder.name(for: current.metadata.createdAt),
            metadata: current.metadata,
            configuration: current.configuration,
            baseline: current.baseline,
            actions: recordedActions,
            samples: recordedSamples
        )
        let data = MotionRecordingEncoder.encode(recording)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(recording.name + ".json", isDirectory: false)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            state = .finished(FinishedRecording(
                url: url,
                sampleCount: recordedSamples.count,
                durationSeconds: max(0, last.timestamp - first.timestamp),
                stopReason: reason
            ))
        } catch {
            Log.persistence.error("Writing the motion recording failed: \(error.localizedDescription, privacy: .public)")
            state = .failed("The recording couldn't be prepared for sharing. Please try again.")
        }
    }

    /// Cancels a recording in progress and deletes the recording file.
    func discard() {
        active = nil
        deadline?.cancel()
        deadline = nil
        samples = []
        actions = []
        MotionRecorder.removeFiles(in: directory)
        if state != .idle {
            state = .idle
        }
    }

    /// Deletes the recordings folder (e.g. a file left behind if the app was terminated).
    nonisolated static func removeFiles(in directory: URL = MotionRecorder.defaultDirectory) {
        let manager = FileManager.default
        if manager.fileExists(atPath: directory.path) {
            try? manager.removeItem(at: directory)
        }
    }

    private func scheduleDeadline(after seconds: TimeInterval) {
        deadline?.cancel()
        let nanoseconds = UInt64(max(seconds, 1) * 1_000_000_000)
        deadline = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            self?.stop(.completed)
        }
    }
}
