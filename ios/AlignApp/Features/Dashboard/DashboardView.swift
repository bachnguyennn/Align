import SwiftUI
import AlignCore

/// Home: sensor status, current tilt, session controls and reminder status (F-05).
@MainActor
struct DashboardView: View {
    @Environment(MonitoringController.self) private var controller
    @Environment(SettingsStore.self) private var settings
    @Environment(ReminderNotifier.self) private var notifier

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.m) {
                    sensorCard
                    if controller.baseline == nil {
                        calibrationPrompt
                    }
                    postureCard
                    sessionCard
                    reminderCard
                }
                .padding(Theme.Spacing.m)
            }
            .background(Theme.background)
            .navigationTitle("Align")
            .onAppear { controller.acquireSensor(.dashboard) }
            .onDisappear { controller.releaseSensor(.dashboard) }
            .task { await notifier.refreshPermission() }
        }
    }

    // MARK: Cards

    private var sensorCard: some View {
        Card {
            CardTitle(controller.sensorSource == .demo ? "Demo sensor" : "AirPods")
            StatusLabel(
                title: controller.connectionState.title,
                systemImage: controller.connectionState.systemImage,
                tint: controller.connectionState.isConnected ? Theme.accent : .secondary
            )
            .font(.headline)
            if let detail = controller.connectionState.detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if controller.sensorSource == .demo {
                Text("Using simulated head motion. Turn off Demo mode in Privacy & Data to use your AirPods.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var calibrationPrompt: some View {
        Card {
            CardTitle("Get started")
            Text("Calibrate your neutral position so Align knows what upright looks like for you.")
                .font(.body)
            NavigationLink {
                CalibrationView()
            } label: {
                WideButtonLabel(title: "Calibrate", systemImage: "scope")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var postureCard: some View {
        Card {
            CardTitle("Head position")
            if let tilt = controller.latestTilt {
                Text(Format.tiltSummary(forward: tilt.forwardDegrees, lateral: tilt.lateralDegrees))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .accessibilityLabel(Format.spokenTilt(forward: tilt.forwardDegrees, lateral: tilt.lateralDegrees))
            } else {
                Text(placeholderText)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            StatusLabel(
                title: controller.postureState.title,
                systemImage: controller.postureState.systemImage,
                tint: controller.isOutsideRange ? Theme.caution : Theme.accent
            )
            NavigationLink {
                LiveMonitoringView()
            } label: {
                Label("Live view", systemImage: "scope")
                    .frame(maxWidth: .infinity, minHeight: Theme.minimumTapTarget, alignment: .leading)
            }
        }
    }

    private var placeholderText: String {
        if controller.baseline == nil {
            return "Calibrate to see your head tilt."
        }
        if !controller.connectionState.isConnected {
            return "Connect your AirPods to see your head tilt."
        }
        return "Waiting for motion data…"
    }

    private var sessionCard: some View {
        Card {
            CardTitle("Monitoring")
            sessionSummary
            sessionButtons
                .padding(.top, Theme.Spacing.xs)
        }
    }

    @ViewBuilder
    private var sessionSummary: some View {
        switch controller.sessionState {
        case .idle:
            if let last = controller.lastFinishedSession {
                Text("Last session: \(Format.duration(last.monitoredSeconds)) monitored, \(Format.percent(last.withinThresholdFraction)) in range.")
                    .font(.body)
            } else {
                Text("Start a session while you sit and work. Align watches for sustained tilts and nudges you. Monitoring runs while Align is open on screen.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        case .running, .paused:
            HStack(alignment: .firstTextBaseline) {
                StatusLabel(
                    title: controller.sessionState == .running ? "Monitoring" : "Paused",
                    systemImage: controller.sessionState == .running ? "dot.radiowaves.left.and.right" : "pause.circle",
                    tint: Theme.accent
                )
                .font(.headline)
                Spacer()
                if let started = controller.sessionStartedAt {
                    Text("since \(started.formatted(date: .omitted, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if controller.pauseReason == .appInactive {
                Text("Paused — Align monitors while the app is open.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: Theme.Spacing.m) {
                metric(title: "Monitored", value: Format.duration(controller.accumulator.monitoredSeconds), spoken: Format.spokenDuration(controller.accumulator.monitoredSeconds))
                metric(title: "In range", value: Format.percent(controller.accumulator.withinThresholdFraction), spoken: Format.percent(controller.accumulator.withinThresholdFraction))
                metric(title: "Reminders", value: "\(controller.accumulator.reminderCount)", spoken: "\(controller.accumulator.reminderCount)")
            }
        }
    }

    private func metric(title: String, value: String, spoken: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(spoken)
    }

    @ViewBuilder
    private var sessionButtons: some View {
        switch controller.sessionState {
        case .idle:
            Button {
                controller.startSession()
            } label: {
                WideButtonLabel(title: "Start monitoring", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!controller.canStartSession)
        case .running:
            HStack(spacing: Theme.Spacing.s) {
                Button {
                    controller.pauseSession()
                } label: {
                    WideButtonLabel(title: "Pause", systemImage: "pause.fill")
                }
                .buttonStyle(.bordered)
                Button(role: .destructive) {
                    controller.stopSession()
                } label: {
                    WideButtonLabel(title: "Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        case .paused:
            HStack(spacing: Theme.Spacing.s) {
                Button {
                    controller.resumeSession()
                } label: {
                    WideButtonLabel(title: "Resume", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(controller.isCalibrating)
                Button(role: .destructive) {
                    controller.stopSession()
                } label: {
                    WideButtonLabel(title: "Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
    }

    private var reminderCard: some View {
        Card {
            CardTitle("Reminders")
            if settings.app.remindersEnabled {
                StatusLabel(
                    title: "On · at most every \(settings.reminderCooldownMinutes) min",
                    systemImage: "bell",
                    tint: Theme.accent
                )
                if let last = controller.lastReminderAt {
                    (Text("Last reminder ") + Text(last, style: .relative) + Text(" ago"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if notifier.permission == .denied {
                    Text("Notifications are turned off for Align in Settings, so reminders only appear while the app is open.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                StatusLabel(title: "Off", systemImage: "bell.slash")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Dashboard") {
    DashboardView()
        .appEnvironment(AppEnvironment.preview())
}
