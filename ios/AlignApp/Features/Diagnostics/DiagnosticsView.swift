import SwiftUI
import AlignCore
import Sensors

/// Phase 0 prototype screen (F-02): live raw sensor values, sample rate and an axis check.
/// Nothing shown here is stored.
@MainActor
struct DiagnosticsView: View {
    @Environment(MonitoringController.self) private var controller
    @Environment(SettingsStore.self) private var settings

    /// Gravity captured with "Capture neutral gravity" for the axis check.
    @State private var neutralGravity: Vector3?

    var body: some View {
        List {
            Section("Sensor") {
                LabeledContent("Source", value: controller.sensorSource == .demo ? "Demo (mock)" : "AirPods")
                LabeledContent("Motion available", value: controller.isMotionAvailable ? "Yes" : "No")
                LabeledContent("Authorization", value: controller.authorization.title)
                LabeledContent("Connection", value: connectionText)
                LabeledContent("Streaming earbud", value: controller.latestSample.map { locationText($0.sensorLocation) } ?? "—")
                LabeledContent("Sample rate", value: rateText)
                LabeledContent("Largest gap", value: gapText)
            }

            Section("Latest sample") {
                LabeledContent("Timestamp", value: controller.latestSample.map { String(format: "%.3f s", $0.timestamp) } ?? "—")
                valueRow("Attitude (x y z w)", controller.latestSample.map { quaternionText($0.attitude) })
                valueRow("Gravity (g)", controller.latestSample?.gravity.map { vectorText($0) })
                valueRow("Rotation rate (rad/s)", controller.latestSample?.rotationRate.map { vectorText($0) })
                valueRow("User acceleration (g)", controller.latestSample?.userAcceleration.map { vectorText($0) })
            }

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
                Axes in use — forward \(vectorText(settings.configuration.axes.forwardAxis)), lateral \(vectorText(settings.configuration.axes.lateralAxis)).
                """)
            }

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
        .onDisappear { controller.releaseSensor(.diagnostics) }
    }

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

#Preview("Diagnostics") {
    NavigationStack {
        DiagnosticsView()
    }
    .appEnvironment(AppEnvironment.preview())
}
