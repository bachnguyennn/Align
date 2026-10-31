import SwiftUI
import UIKit
import AlignCore

/// Captures the user's neutral head position (F-04).
@MainActor
struct CalibrationView: View {
    @Environment(MonitoringController.self) private var controller
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                content
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("Calibrate")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            controller.acknowledgeCalibrationResult()
            controller.acquireSensor(.calibration)
        }
        .onDisappear {
            controller.cancelCalibration()
            controller.acknowledgeCalibrationResult()
            controller.releaseSensor(.calibration)
        }
        .onChange(of: controller.calibrationPhase) { _, phase in
            announce(phase)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch controller.calibrationPhase {
        case .idle:
            instructions
            connectionStatus
            Button {
                controller.startCalibration()
            } label: {
                WideButtonLabel(title: "Start calibration", systemImage: "scope")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!controller.connectionState.isConnected)
            if controller.sessionState == .running {
                Text("Monitoring will pause while you calibrate.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

        case .waitingForSensor:
            ProgressRing(progress: 0)
            Text("Waiting for your AirPods…")
                .font(.headline)
            connectionStatus
            cancelButton

        case .inProgress(let progress):
            ProgressRing(progress: progress)
            Text("Hold still and look straight ahead")
                .font(.headline)
                .multilineTextAlignment(.center)
            cancelButton

        case .succeeded(let baseline):
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("Calibrated")
                .font(.title2.weight(.semibold))
            Text("Your neutral position is saved (calibration \(baseline.version)). Recalibrate any time your setup changes, for example a new chair or desk.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button {
                dismiss()
            } label: {
                WideButtonLabel(title: "Done", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

        case .failed(let reason):
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.caution)
                .accessibilityHidden(true)
            Text("Calibration didn't finish")
                .font(.title2.weight(.semibold))
            Text(reason.message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button {
                controller.acknowledgeCalibrationResult()
                controller.startCalibration()
            } label: {
                WideButtonLabel(title: "Try again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!controller.connectionState.isConnected)
        }
    }

    private var instructions: some View {
        Card {
            CardTitle("Before you start")
            instructionRow(number: 1, text: "Sit comfortably upright, the way you'd like to sit while you work.")
            instructionRow(number: 2, text: "Look straight ahead at something at eye level.")
            instructionRow(number: 3, text: "Hold still for about \(Int(settings.configuration.calibrationDuration)) seconds.")
            if let baseline = controller.baseline {
                Text("Last calibrated \(baseline.capturedAt.formatted(date: .abbreviated, time: .shortened)).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, Theme.Spacing.xs)
            }
        }
    }

    private func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            Text("\(number).")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.accent)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var connectionStatus: some View {
        if !controller.connectionState.isConnected {
            Card {
                StatusLabel(title: controller.connectionState.title, systemImage: controller.connectionState.systemImage)
                if let detail = controller.connectionState.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var cancelButton: some View {
        Button("Cancel", role: .cancel) {
            controller.cancelCalibration()
        }
        .frame(minHeight: Theme.minimumTapTarget)
    }

    private func announce(_ phase: CalibrationPhase) {
        let message: String
        switch phase {
        case .succeeded:
            message = "Calibration complete"
        case .failed(let reason):
            message = "Calibration didn't finish. \(reason.message)"
        case .inProgress(let progress) where progress == 0:
            message = "Calibration started. Hold still."
        default:
            return
        }
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

/// Circular progress for calibration.
struct ProgressRing: View {
    var progress: Double

    var body: some View {
        let clamped = min(max(progress, 0), 1)
        ZStack {
            Circle()
                .stroke(Theme.hairline, lineWidth: 10)
            Circle()
                .trim(from: 0, to: CGFloat(clamped))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((clamped * 100).rounded()))%")
                .font(.title2.weight(.semibold))
                .monospacedDigit()
        }
        .frame(width: 160, height: 160)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calibration progress")
        .accessibilityValue("\(Int((clamped * 100).rounded())) percent")
    }
}

#Preview("Calibration") {
    NavigationStack {
        CalibrationView()
    }
    .appEnvironment(AppEnvironment.preview())
}
