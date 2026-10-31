import SwiftUI
import AlignCore
import Sensors

/// Live head-orientation view with numeric readouts (F-05).
@MainActor
struct LiveMonitoringView: View {
    @Environment(MonitoringController.self) private var controller
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                HeadOrientationIndicator(
                    forwardDegrees: controller.latestTilt?.forwardDegrees,
                    lateralDegrees: controller.latestTilt?.lateralDegrees,
                    forwardThreshold: settings.configuration.forwardThresholdDegrees,
                    backwardThreshold: settings.configuration.backwardThresholdDegrees,
                    lateralThreshold: settings.configuration.lateralThresholdDegrees,
                    isOutsideRange: controller.isOutsideRange
                )
                .frame(maxWidth: 320)
                .padding(.horizontal, Theme.Spacing.m)

                StatusLabel(
                    title: controller.postureState.title,
                    systemImage: controller.postureState.systemImage,
                    tint: controller.isOutsideRange ? Theme.caution : Theme.accent
                )
                .font(.headline)

                readouts

                if controller.baseline == nil {
                    Card {
                        Text("Calibrate first so tilt can be measured from your own neutral position.")
                        NavigationLink {
                            CalibrationView()
                        } label: {
                            WideButtonLabel(title: "Calibrate", systemImage: "scope")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                } else if !controller.connectionState.isConnected {
                    Card {
                        StatusLabel(title: controller.connectionState.title, systemImage: controller.connectionState.systemImage)
                        if let detail = controller.connectionState.detail {
                            Text(detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if controller.sensorSource == .demo {
                    DemoControlsView()
                }

                Text("The dashed outline shows your reminder angles. Short glances past it are fine; Align only reminds you when a tilt lasts \(Int(settings.configuration.sustainedDuration)) seconds.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Theme.Spacing.m)
        }
        .background(Theme.background)
        .navigationTitle("Live view")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { controller.acquireSensor(.liveView) }
        .onDisappear { controller.releaseSensor(.liveView) }
    }

    private var readouts: some View {
        HStack(spacing: Theme.Spacing.m) {
            readout(
                title: "Forward",
                value: controller.latestTilt.map { Format.signedDegrees($0.forwardDegrees) } ?? "—",
                limit: "limit \(Int(settings.configuration.forwardThresholdDegrees))°"
            )
            readout(
                title: "Sideways",
                value: controller.latestTilt.map { Format.signedDegrees($0.lateralDegrees) } ?? "—",
                limit: "limit \(Int(settings.configuration.lateralThresholdDegrees))°"
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tilt")
        .accessibilityValue(readoutAccessibilityValue)
    }

    private var readoutAccessibilityValue: String {
        guard let tilt = controller.latestTilt else { return "No tilt data" }
        return Format.spokenTilt(forward: tilt.forwardDegrees, lateral: tilt.lateralDegrees)
    }

    private func readout(title: String, value: String, limit: String) -> some View {
        Card {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title.weight(.semibold))
                .monospacedDigit()
            Text(limit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Controls for the mock sensor: scenario picker and manual tilt sliders.
@MainActor
struct DemoControlsView: View {
    @Environment(MonitoringController.self) private var controller

    var body: some View {
        @Bindable var controller = controller
        Card {
            CardTitle("Demo sensor")
            Picker("Scenario", selection: $controller.demoScenario) {
                ForEach(MockScenario.allCases, id: \.self) { scenario in
                    Text(scenario.displayName).tag(scenario)
                }
            }
            .pickerStyle(.menu)
            .frame(minHeight: Theme.minimumTapTarget)

            if controller.demoScenario == .manual {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Forward tilt: \(Int(controller.demoForwardDegrees))°")
                        .monospacedDigit()
                    Slider(value: $controller.demoForwardDegrees, in: -30...40, step: 1) {
                        Text("Forward tilt")
                    }
                    .accessibilityValue("\(Int(controller.demoForwardDegrees)) degrees")
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Sideways tilt: \(Int(controller.demoLateralDegrees))°")
                        .monospacedDigit()
                    Slider(value: $controller.demoLateralDegrees, in: -30...30, step: 1) {
                        Text("Sideways tilt")
                    }
                    .accessibilityValue("\(Int(controller.demoLateralDegrees)) degrees")
                }
                Button("Back to neutral") {
                    controller.resetDemoTilt()
                }
                .frame(minHeight: Theme.minimumTapTarget)
            }
        }
    }
}

#Preview("Live view") {
    NavigationStack {
        LiveMonitoringView()
    }
    .appEnvironment(AppEnvironment.preview())
}
