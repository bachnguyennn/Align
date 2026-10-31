import SwiftUI

/// What Align stores, deletion, calibration reset and demo mode (F-09).
@MainActor
struct PrivacyDataView: View {
    @Environment(MonitoringController.self) private var controller
    @Environment(SettingsStore.self) private var settings

    @State private var confirmDeleteHistory = false
    @State private var confirmResetCalibration = false
    @State private var statusMessage: String?

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                privacyRow(
                    systemImage: "iphone",
                    title: "Processed on your iPhone",
                    text: "Head motion from your AirPods is analyzed on this iPhone as it arrives. Raw motion data is not saved and never leaves the device."
                )
                privacyRow(
                    systemImage: "icloud.slash",
                    title: "No account, no uploads",
                    text: "Align has no account and sends nothing to a server."
                )
            } header: {
                Text("Your data")
            }

            Section {
                bullet("Session summaries: start and end time, time monitored, time within range, time in a sustained tilt, reminder count.")
                bullet("Sustained tilts: when they started and ended, direction and largest angle.")
                bullet("Your calibrated neutral position and your reminder settings.")
            } header: {
                Text("What Align stores")
            } footer: {
                Text("Stored only on this iPhone. Deleting the app removes everything.")
            }

            Section {
                Button("Delete all history", role: .destructive) {
                    confirmDeleteHistory = true
                }
                .frame(minHeight: Theme.minimumTapTarget)
                Button("Reset calibration", role: .destructive) {
                    confirmResetCalibration = true
                }
                .frame(minHeight: Theme.minimumTapTarget)
                .disabled(controller.baseline == nil)
                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Manage data")
            } footer: {
                if controller.sessionState != .idle {
                    Text("The current session will be stopped first.")
                }
            }

            Section {
                Toggle("Demo mode", isOn: $settings.app.demoModeEnabled)
                    .disabled(BuildEnvironment.isSimulator)
            } header: {
                Text("Demo")
            } footer: {
                if BuildEnvironment.isSimulator {
                    Text("The simulator always uses simulated head motion.")
                } else {
                    Text("Uses simulated head motion instead of your AirPods, so you can try Align without them. Demo sessions are marked as such in History.")
                }
            }
        }
        .navigationTitle("Privacy & data")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete all history?", isPresented: $confirmDeleteHistory, titleVisibility: .visible) {
            Button("Delete all history", role: .destructive) {
                controller.deleteAllHistory()
                statusMessage = "History deleted."
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All sessions and tilt records are removed from this iPhone. This can't be undone.")
        }
        .confirmationDialog("Reset calibration?", isPresented: $confirmResetCalibration, titleVisibility: .visible) {
            Button("Reset calibration", role: .destructive) {
                controller.resetCalibration()
                statusMessage = "Calibration reset. Calibrate again before your next session."
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your saved neutral position is removed. You'll need to calibrate again before monitoring.")
        }
    }

    private func privacyRow(systemImage: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func bullet(_ text: String) -> some View {
        Label {
            Text(text)
                .font(.subheadline)
        } icon: {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("Privacy") {
    NavigationStack {
        PrivacyDataView()
    }
    .appEnvironment(AppEnvironment.preview())
}
