import SwiftUI
import UIKit
import AlignCore

/// Example headphones with head tracking, per docs/research/airpods-motion-feasibility.md §3.
/// Compatibility is decided at runtime (samples arrive), not by this list.
enum SupportedHeadphones {
    static let examples: [String] = [
        "AirPods Pro",
        "AirPods Max",
        "AirPods (3rd generation or later)",
    ]
}

/// AirPods compatibility and permissions (F-03). Used in onboarding and from Settings.
@MainActor
struct PermissionsView: View {
    @Environment(MonitoringController.self) private var controller
    @Environment(ReminderNotifier.self) private var notifier
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                LabeledContent("Headphone motion", value: controller.isMotionAvailable ? "Available" : "Not available")
                LabeledContent("Motion access", value: controller.authorization.title)
                LabeledContent("Status", value: controller.connectionState.title)
                if controller.sensorSource == .demo {
                    Text("Demo mode is on, so Align is using simulated head motion.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                motionAction
            } header: {
                Text("AirPods motion")
            } footer: {
                Text("Align reads head tilt from your AirPods' motion sensors. iOS asks for Motion & Fitness access the first time.")
            }

            Section {
                LabeledContent("Notifications", value: notificationText)
                notificationAction
            } header: {
                Text("Reminders")
            } footer: {
                Text("Reminders are quiet local notifications from this iPhone. Align monitors only while the app is open.")
            }

            Section {
                ForEach(SupportedHeadphones.examples, id: \.self) { model in
                    Label(model, systemImage: "airpodspro")
                }
            } header: {
                Text("Works with headphones that support head tracking, such as")
            } footer: {
                Text("Requires iOS 17 or later on iPhone. If your headphones connect but Align shows no motion, they may not share head-tracking data with apps.")
            }

            Section("If something isn't working") {
                tip("Wear both AirPods and check they're connected to this iPhone in Control Center.")
                tip("Make sure Motion & Fitness access is on for Align in Settings › Privacy & Security › Motion & Fitness.")
                tip("Put the AirPods back in the case for a few seconds, then reconnect.")
                tip("Keep your AirPods firmware and iOS up to date.")
                tip("Keep Align open on screen while monitoring.")
            }
        }
        .navigationTitle("AirPods & permissions")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            controller.refreshProviderStatus()
            await notifier.refreshPermission()
        }
        .onDisappear { controller.releaseSensor(.permissions) }
    }

    @ViewBuilder
    private var motionAction: some View {
        switch controller.authorization {
        case .notDetermined:
            Button("Allow motion access") {
                // Starting the sensor makes iOS show the Motion & Fitness prompt.
                controller.acquireSensor(.permissions)
            }
            .frame(minHeight: Theme.minimumTapTarget)
            .disabled(!controller.isMotionAvailable)
        case .denied, .restricted:
            Button("Open Settings") { openSettings() }
                .frame(minHeight: Theme.minimumTapTarget)
        case .authorized:
            if !controller.isStreaming {
                Button("Check AirPods connection") {
                    controller.acquireSensor(.permissions)
                }
                .frame(minHeight: Theme.minimumTapTarget)
            }
        }
    }

    @ViewBuilder
    private var notificationAction: some View {
        switch notifier.permission {
        case .notDetermined:
            Button("Allow notifications") {
                Task { await notifier.requestPermission() }
            }
            .frame(minHeight: Theme.minimumTapTarget)
        case .denied:
            Button("Open Settings") { openSettings() }
                .frame(minHeight: Theme.minimumTapTarget)
        case .authorized, .unknown:
            EmptyView()
        }
    }

    private var notificationText: String {
        switch notifier.permission {
        case .unknown: return "Checking…"
        case .notDetermined: return "Not requested yet"
        case .denied: return "Off"
        case .authorized: return "Allowed"
        }
    }

    private func tip(_ text: String) -> some View {
        Label {
            Text(text)
                .font(.subheadline)
        } icon: {
            Image(systemName: "lightbulb")
                .foregroundStyle(Theme.accent)
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}

#Preview("Permissions") {
    NavigationStack {
        PermissionsView()
    }
    .appEnvironment(AppEnvironment.preview())
}
