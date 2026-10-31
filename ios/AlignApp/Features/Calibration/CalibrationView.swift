import SwiftUI
import UIKit
import AlignCore

/// Captures the user's neutral head position (F-04), then a guided nod that learns the tilt axes
/// for how the AirPods sit right now (F-11, D-017 (a)). Also the Settings → Neutral position
/// screen: shows whether the axes are learned or default, with "Redo nod" and "Use default axes".
@MainActor
struct CalibrationView: View {
    @Environment(MonitoringController.self) private var controller
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// "Redo nod" was tapped on the instructions screen: show the nod step without a new
    /// neutral calibration.
    @State private var nodRequested = false

    private static let nodInstruction = "Now nod slowly — chin down about 20–30°, then back up."

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
            nodRequested = false
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
        .onChange(of: controller.axisCalibrationPhase) { _, phase in
            announceNod(phase)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch controller.calibrationPhase {
        case .idle:
            if nodRequested || controller.axisCalibrationPhase != .idle {
                nodStep(afterNeutral: false)
            } else {
                idleContent
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
            Text("Step 1 of 2")
                .font(.footnote)
                .foregroundStyle(.secondary)
            cancelButton

        case .succeeded:
            // Step 2: the guided nod. The neutral baseline is already saved.
            nodStep(afterNeutral: true)

        case .failed(let reason):
            resultHeader(systemImage: "exclamationmark.triangle.fill", tint: Theme.caution, title: "Calibration didn't finish")
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

    // MARK: Step 1: instructions

    @ViewBuilder
    private var idleContent: some View {
        instructions
        axesCard
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
    }

    private var instructions: some View {
        Card {
            CardTitle("Before you start")
            instructionRow(number: 1, text: "Sit comfortably upright, the way you'd like to sit while you work.")
            instructionRow(number: 2, text: "Look straight ahead at something at eye level.")
            instructionRow(number: 3, text: "Hold still for about \(Int(settings.configuration.calibrationDuration)) seconds.")
            instructionRow(number: 4, text: "Then nod slowly once, so Align learns how your AirPods sit.")
            if let baseline = controller.baseline {
                Text("Last calibrated \(baseline.capturedAt.formatted(date: .abbreviated, time: .shortened)).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, Theme.Spacing.xs)
            }
        }
    }

    /// Whether the tilt axes come from a nod, with "Redo nod" and "Use default axes".
    @ViewBuilder
    private var axesCard: some View {
        if controller.baseline != nil {
            Card {
                CardTitle("Tilt axes")
                LabeledContent("Axes", value: HeadAxisConvention.sourceTitle(learned: controller.hasLearnedAxes))
                Text(controller.hasLearnedAxes
                     ? "Learned from your nod for how your AirPods sit now. A new calibration starts again from the default axes."
                     : "Without a nod, Align uses default axes. A nod helps when your AirPods sit slightly turned in your ears.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    nodRequested = true
                } label: {
                    Label(controller.hasLearnedAxes ? "Redo nod" : "Do the nod", systemImage: "arrow.up.and.down")
                        .frame(minHeight: Theme.minimumTapTarget)
                }
                if controller.hasLearnedAxes {
                    Button {
                        controller.useDefaultAxes()
                        UIAccessibility.post(notification: .announcement, argument: "Using the default axes")
                    } label: {
                        Label("Use default axes", systemImage: "arrow.uturn.backward")
                            .frame(minHeight: Theme.minimumTapTarget)
                    }
                }
            }
        }
    }

    // MARK: Step 2: guided nod

    @ViewBuilder
    private func nodStep(afterNeutral: Bool) -> some View {
        switch controller.axisCalibrationPhase {
        case .idle:
            nodIntro(afterNeutral: afterNeutral)

        case .waitingForSensor:
            NodIllustration(animated: !reduceMotion)
            Text("Waiting for your AirPods…")
                .font(.headline)
            connectionStatus
            nodSecondaryButton(afterNeutral: afterNeutral)

        case .inProgress(let progress):
            NodIllustration(animated: !reduceMotion)
            Text(CalibrationView.nodInstruction)
                .font(.headline)
                .multilineTextAlignment(.center)
            ProgressView(value: min(max(progress, 0), 1)) {
                Text("Watching for your nod…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Nod step progress")
            .accessibilityValue("\(Int((min(max(progress, 0), 1) * 100).rounded())) percent")
            nodSecondaryButton(afterNeutral: afterNeutral)

        case .succeeded:
            resultHeader(systemImage: "checkmark.circle.fill", tint: Theme.accent, title: "All set")
            Text(afterNeutral
                 ? "Your neutral position and your nod are saved. Align now measures tilt along the axes learned from your nod."
                 : "Your nod is saved. Align now measures tilt along the axes learned from it.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Recalibrate any time your setup changes, for example a new chair or desk, or after putting your AirPods back in.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            doneButton

        case .failed(let reason):
            resultHeader(systemImage: "exclamationmark.triangle.fill", tint: Theme.caution, title: reason.title)
            Text(reason.message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if reason == .needsBaseline {
                Button {
                    nodRequested = false
                    controller.acknowledgeCalibrationResult()
                    controller.startCalibration()
                } label: {
                    WideButtonLabel(title: "Calibrate neutral position", systemImage: "scope")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!controller.connectionState.isConnected)
            } else {
                Button {
                    controller.startAxisCalibration()
                } label: {
                    WideButtonLabel(title: "Try the nod again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!controller.connectionState.isConnected)
            }
            connectionStatus
            nodSecondaryButton(afterNeutral: afterNeutral)

        case .skipped:
            resultHeader(systemImage: "checkmark.circle.fill", tint: Theme.accent, title: "Calibrated")
            if let baseline = controller.baseline {
                Text("Your neutral position is saved (calibration \(baseline.version)). Align is using the default axes; you can add the nod any time in Settings → Neutral position.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            doneButton
        }
    }

    @ViewBuilder
    private func nodIntro(afterNeutral: Bool) -> some View {
        if afterNeutral {
            StatusLabel(title: "Neutral position saved", systemImage: "checkmark.circle.fill", tint: Theme.accent)
                .font(.headline)
        }
        Card {
            CardTitle(afterNeutral ? "Step 2 of 2: one slow nod" : "Redo the nod")
            Text(CalibrationView.nodInstruction)
                .font(.body.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("This shows Align how your AirPods sit in your ears, so forward and sideways tilts are measured along the right axes. You have about \(Int(settings.configuration.axisCalibrationDuration)) seconds after you tap Start.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        NodIllustration(animated: !reduceMotion)
        connectionStatus
        Button {
            controller.startAxisCalibration()
        } label: {
            WideButtonLabel(title: "Start the nod", systemImage: "arrow.up.and.down")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!controller.connectionState.isConnected)
        nodSecondaryButton(afterNeutral: afterNeutral)
        if afterNeutral {
            Text("Skipping keeps the default axes. You can add the nod later in Settings → Neutral position.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    /// "Skip" right after a neutral calibration (keeps the default axes); "Cancel" when only the
    /// nod is being redone (keeps whatever axes were in use).
    @ViewBuilder
    private func nodSecondaryButton(afterNeutral: Bool) -> some View {
        if afterNeutral {
            Button("Skip") {
                controller.skipAxisCalibration()
            }
            .frame(minHeight: Theme.minimumTapTarget)
            .accessibilityHint("Keeps the default axes")
        } else {
            Button("Cancel", role: .cancel) {
                controller.cancelAxisCalibration()
                controller.acknowledgeCalibrationResult()
                nodRequested = false
            }
            .frame(minHeight: Theme.minimumTapTarget)
        }
    }

    // MARK: Shared pieces

    private func resultHeader(systemImage: String, tint: Color, title: String) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: systemImage)
                .font(.system(size: 60))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var doneButton: some View {
        Button {
            dismiss()
        } label: {
            WideButtonLabel(title: "Done", systemImage: "checkmark")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
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
            message = "Neutral position saved. Next, one slow nod."
        case .failed(let reason):
            message = "Calibration didn't finish. \(reason.message)"
        case .inProgress(let progress) where progress == 0:
            message = "Calibration started. Hold still."
        default:
            return
        }
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private func announceNod(_ phase: AxisCalibrationPhase) {
        let message: String
        switch phase {
        case .inProgress(let progress) where progress == 0:
            message = "Nod now. Chin down slowly, then back up."
        case .succeeded:
            message = "Nod recognized. Your axes are saved."
        case .failed(let reason):
            message = "\(reason.title). \(reason.message)"
        case .skipped:
            message = "Nod skipped. Using the default axes."
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

/// A head in profile (facing right) nodding chin-down and back up. With Reduce Motion it is
/// static: the upright head plus a faint copy in the nodded position.
struct NodIllustration: View {
    var animated: Bool

    private static let nodDegrees: Double = 25

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if animated {
                    PhaseAnimator([0.0, NodIllustration.nodDegrees]) { angle in
                        head
                            .rotationEffect(.degrees(angle), anchor: .bottom)
                    } animation: { _ in
                        Animation.easeInOut(duration: 1.3)
                    }
                } else {
                    head
                        .opacity(0.3)
                        .rotationEffect(.degrees(NodIllustration.nodDegrees), anchor: .bottom)
                    head
                }
            }
            .frame(width: 128, height: 96)
            Capsule()
                .fill(Theme.accent.opacity(0.55))
                .frame(width: 30, height: 34)
        }
        .padding(.vertical, Theme.Spacing.s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Illustration of a head nodding: chin down toward the chest, then back up")
        .accessibilityAddTraits(.isImage)
    }

    private var head: some View {
        ZStack {
            Circle()
                .fill(Theme.accent)
            NoseShape()
                .fill(Theme.accent)
                .frame(width: 16, height: 22)
                .offset(x: 51, y: 4)
            Circle()
                .fill(Theme.cardBackground)
                .frame(width: 9, height: 9)
                .offset(x: 22, y: -12)
        }
        .frame(width: 96, height: 96)
    }
}

/// A small triangle pointing right, used as the nose of `NodIllustration`.
private struct NoseShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.6))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview("Calibration") {
    NavigationStack {
        CalibrationView()
    }
    .appEnvironment(AppEnvironment.preview())
}

#Preview("Nod illustration") {
    VStack {
        NodIllustration(animated: true)
        NodIllustration(animated: false)
    }
}
