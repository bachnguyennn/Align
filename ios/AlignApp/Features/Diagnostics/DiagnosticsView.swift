import SwiftUI
import AlignCore
import Sensors

/// Phase 0 prototype screen (F-02): live raw sensor values, sample rate, the tilt axes in use and
/// an axis check. Nothing shown here is stored, except an opt-in motion recording (F-11,
/// D-017 (d)) that lives in a temporary file until the user leaves this screen.
@MainActor
struct DiagnosticsView: View {
    @Environment(MonitoringController.self) private var controller
    @Environment(SettingsStore.self) private var settings

    /// Gravity captured with "Capture neutral gravity" for the axis check.
    @State private var neutralGravity: Vector3?
    /// Recording controls. Kept here, not in the section view, because List rows are created
    /// lazily and the recording must be discarded when this whole screen goes away.
    @State private var recordingLength: RecordingLength = .twoMinutes
    @State private var recordingNotes = ""
    @State private var startedCalibrationHere = false

    var body: some View {
        List {
            sensorSection
            latestSampleSection
            monitorSection
            axesSection
            axisCheckSection
            MotionRecordingSection(
                length: $recordingLength,
                notes: $recordingNotes,
                startedCalibrationHere: $startedCalibrationHere
            )

            if controller.sensorSource == .demo {
                Section {
                    DemoControlsView()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { controller.acquireSensor(.diagnostics) }
        .onDisappear {
            // The recording file never outlives this screen (D-017 (d)).
            controller.discardRecording()
            if startedCalibrationHere {
                controller.cancelCalibration()
                controller.acknowledgeCalibrationResult()
                startedCalibrationHere = false
            }
            controller.releaseSensor(.diagnostics)
        }
    }

    // MARK: Sections

    private var sensorSection: some View {
        Section("Sensor") {
            LabeledContent("Source", value: controller.sensorSource == .demo ? "Demo (mock)" : "AirPods")
            LabeledContent("Motion available", value: controller.isMotionAvailable ? "Yes" : "No")
            LabeledContent("Authorization", value: controller.authorization.title)
            LabeledContent("Connection", value: connectionText)
            LabeledContent("Streaming earbud", value: controller.latestSample.map { locationText($0.sensorLocation) } ?? "—")
            LabeledContent("Sample rate", value: rateText)
            LabeledContent("Largest gap", value: gapText)
            LabeledContent("Sample watchdog", value: controller.isSampleStalled ? "No samples, interrupted" : "OK")
            LabeledContent("Stalls since launch", value: "\(controller.sampleStallCount)")
        }
    }

    private var latestSampleSection: some View {
        Section("Latest sample") {
            LabeledContent("Timestamp", value: controller.latestSample.map { String(format: "%.3f s", $0.timestamp) } ?? "—")
            valueRow("Attitude (x y z w)", controller.latestSample.map { quaternionText($0.attitude) })
            valueRow("Gravity (g)", controller.latestSample?.gravity.map { vectorText($0) })
            valueRow("Rotation rate (rad/s)", controller.latestSample?.rotationRate.map { vectorText($0) })
            valueRow("User acceleration (g)", controller.latestSample?.userAcceleration.map { vectorText($0) })
        }
    }

    private var monitorSection: some View {
        Section {
            if let tilt = controller.latestTilt {
                LabeledContent("Forward", value: Format.signedDegrees(tilt.forwardDegrees))
                LabeledContent("Lateral", value: Format.signedDegrees(tilt.lateralDegrees))
                LabeledContent("Total", value: Format.signedDegrees(tilt.totalDegrees))
            } else {
                Text(controller.baseline == nil ? "Calibrate to see the monitor's tilt." : "Waiting for samples.")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("State", value: controller.postureState.title)
        } header: {
            Text("Posture monitor (calibrated)")
        }
    }

    /// The axes the monitor uses (D-017): learned from the nod or the default convention.
    private var axesSection: some View {
        Section {
            LabeledContent("Axes", value: HeadAxisConvention.sourceTitle(learned: controller.hasLearnedAxes))
            valueRow("Forward axis", vectorText(controller.effectiveAxes.forwardAxis))
            valueRow("Lateral axis", vectorText(controller.effectiveAxes.lateralAxis))
            LabeledContent("Learned yaw vs default", value: controller.learnedAxisYawDegrees.map { Format.signedDegrees($0) } ?? "—")
        } header: {
            Text("Tilt axes in use")
        } footer: {
            Text("Yaw is the angle between the learned and the default forward axis, measured in the plane level with your neutral head position: roughly how far your AirPods sit turned in your ears. Positive means turned toward the default lateral axis. Redo the nod in Settings → Neutral position.")
        }
    }

    private var axisCheckSection: some View {
        Section {
            Button(neutralGravity == nil ? "Capture neutral gravity" : "Capture again") {
                neutralGravity = controller.latestSample?.gravity
            }
            .disabled(controller.latestSample?.gravity == nil)
            .frame(minHeight: Theme.minimumTapTarget)

            if let neutral = neutralGravity {
                valueRow("Captured gravity", vectorText(neutral))
                if let current = controller.latestSample?.gravity,
                   let result = AxisCheck.tilt(neutralGravity: neutral, currentGravity: current, axes: settings.configuration.axes) {
                    LabeledContent("Forward", value: Format.signedDegrees(result.forwardDegrees))
                    LabeledContent("Lateral", value: Format.signedDegrees(result.lateralDegrees))
                    LabeledContent("Total", value: Format.signedDegrees(result.totalDegrees))
                }
            }
        } header: {
            Text("Axis check")
        } footer: {
            Text("""
            1. Sit upright, look straight ahead and tap Capture neutral gravity.
            2. Nod down (chin toward chest): Forward should become positive.
            3. Look up: Forward should become negative.
            4. Tilt your right ear toward your right shoulder: Lateral should become positive.
            5. Turn your head left and right: both should stay near zero.
            This check always uses the default axes — forward \(vectorText(settings.configuration.axes.forwardAxis)), lateral \(vectorText(settings.configuration.axes.lateralAxis)).
            """)
        }
    }

    // MARK: Formatting

    private func valueRow(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(value ?? "—")
                .font(.system(.body, design: .monospaced))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private var connectionText: String {
        switch controller.connectionState {
        case .failed(let message):
            return "Failed: \(message)"
        default:
            return controller.connectionState.title
        }
    }

    private var rateText: String {
        guard let rate = controller.rateMeter.samplesPerSecond else { return "—" }
        return String(format: "%.1f Hz", rate)
    }

    private var gapText: String {
        guard let gap = controller.rateMeter.largestGap else { return "—" }
        return String(format: "%.0f ms", gap * 1000)
    }

    private func locationText(_ location: SensorLocation) -> String {
        switch location {
        case .unknown: return "Unknown"
        case .headphoneLeft: return "Left"
        case .headphoneRight: return "Right"
        }
    }

    private func vectorText(_ v: Vector3) -> String {
        String(format: "%+.3f %+.3f %+.3f", v.x, v.y, v.z)
    }

    private func quaternionText(_ q: Quaternion) -> String {
        String(format: "%+.3f %+.3f %+.3f %+.3f", q.x, q.y, q.z, q.w)
    }
}

/// "Record motion" (D-017 (d)): explanation, length and notes, then progress, then a share link.
@MainActor
struct MotionRecordingSection: View {
    @Environment(MonitoringController.self) private var controller

    @Binding var length: RecordingLength
    @Binding var notes: String
    @Binding var startedCalibrationHere: Bool

    private static let maxNotesLength = 280

    var body: some View {
        Section {
            switch controller.recorder.state {
            case .idle, .failed:
                setup
            case .recording(let recordingLength, let elapsed, let sampleCount):
                recording(length: recordingLength, elapsed: elapsed, sampleCount: sampleCount)
            case .finished(let file):
                finished(file)
            }
        } header: {
            Text("Record motion")
        } footer: {
            Text("For tuning Align on real data: one recording sitting upright, one slouching at a desk and one looking at a phone help most. See TESTING.md.")
        }
    }

    @ViewBuilder
    private var setup: some View {
        Text("This records the raw head motion from your AirPods, plus your current calibration, only to export it. The recording stays on this iPhone in a temporary file unless you share it, and it is deleted when you leave this screen. Align never uploads it.")
            .font(.footnote)
            .fixedSize(horizontal: false, vertical: true)
        Picker("Length", selection: $length) {
            ForEach(RecordingLength.allCases) { option in
                Text(option.title)
                    .accessibilityLabel(option.spokenTitle)
                    .tag(option)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Recording length")
        TextField("Notes (optional), e.g. slouching at desk", text: $notes, axis: .vertical)
            .lineLimit(1...4)
            .onChange(of: notes) { _, newValue in
                if newValue.count > MotionRecordingSection.maxNotesLength {
                    notes = String(newValue.prefix(MotionRecordingSection.maxNotesLength))
                }
            }
        Text("Keep notes free of names or other personal details.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        Button {
            controller.startRecording(length: length, notes: notes)
        } label: {
            Label("Start recording", systemImage: "record.circle")
                .frame(minHeight: Theme.minimumTapTarget)
        }
        .disabled(!controller.canStartRecording)
        if !controller.connectionState.isConnected {
            Text("Connect your AirPods to record.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        if case .failed(let message) = controller.recorder.state {
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.caution)
        }
    }

    @ViewBuilder
    private func recording(length: RecordingLength, elapsed: TimeInterval, sampleCount: Int) -> some View {
        ProgressView(value: min(elapsed, length.seconds), total: length.seconds) {
            Text("Recording… \(Int(elapsed)) of \(Int(length.seconds)) s")
        }
        .accessibilityLabel("Recording")
        .accessibilityValue("\(Int(elapsed)) of \(Int(length.seconds)) seconds")
        LabeledContent("Samples", value: "\(sampleCount)")

        // Calibrating while recording puts the calibration itself into the file (actions).
        Button {
            startedCalibrationHere = true
            controller.startCalibration(client: .diagnostics)
        } label: {
            Label("Calibrate neutral now", systemImage: "scope")
                .frame(minHeight: Theme.minimumTapTarget)
        }
        .disabled(controller.isCalibrating || !controller.connectionState.isConnected)
        Button {
            startedCalibrationHere = true
            controller.startAxisCalibration(client: .diagnostics)
        } label: {
            Label("Nod now", systemImage: "arrow.up.and.down")
                .frame(minHeight: Theme.minimumTapTarget)
        }
        .disabled(controller.isCalibrating || controller.baseline == nil || !controller.connectionState.isConnected)
        if let status = calibrationStatus {
            Text(status)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Button(role: .destructive) {
            controller.stopRecording()
        } label: {
            Label("Stop recording", systemImage: "stop.circle")
                .frame(minHeight: Theme.minimumTapTarget)
        }
    }

    @ViewBuilder
    private func finished(_ file: FinishedRecording) -> some View {
        StatusLabel(title: "Recording ready", systemImage: "checkmark.circle.fill", tint: Theme.accent)
        LabeledContent("Samples", value: "\(file.sampleCount)")
        LabeledContent("Length", value: Format.duration(file.durationSeconds))
        if let message = file.stopReason.message {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        ShareLink(item: file.url) {
            Label("Share recording", systemImage: "square.and.arrow.up")
                .frame(minHeight: Theme.minimumTapTarget)
        }
        Button(role: .destructive) {
            controller.discardRecording()
        } label: {
            Label("Delete recording", systemImage: "trash")
                .frame(minHeight: Theme.minimumTapTarget)
        }
        Text("Only you decide where it goes. The file is deleted when you leave this screen or start a new recording.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var calibrationStatus: String? {
        switch controller.axisCalibrationPhase {
        case .waitingForSensor, .inProgress:
            return "Nod now: chin down slowly about 20–30°, then back up."
        case .succeeded:
            return "Nod recognized; learned axes saved."
        case .failed(let reason):
            return reason.message
        case .idle, .skipped:
            break
        }
        switch controller.calibrationPhase {
        case .waitingForSensor:
            return "Waiting for your AirPods…"
        case .inProgress(let progress):
            return "Calibrating: hold still and look ahead (\(Format.percent(progress)))."
        case .succeeded(let baseline):
            return "Neutral position saved (calibration \(baseline.version))."
        case .failed(let reason):
            return reason.message
        case .idle:
            return nil
        }
    }
}

#Preview("Diagnostics") {
    NavigationStack {
        DiagnosticsView()
    }
    .appEnvironment(AppEnvironment.preview())
}
