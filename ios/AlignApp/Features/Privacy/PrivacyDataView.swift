import SwiftUI

/// What Align stores, deletion, calibration reset and demo mode (F-09).
@MainActor
struct PrivacyDataView: View {
    @Environment(MonitoringController.self) private var controller
    @Environment(SettingsStore.self) private var settings

    @State private var confirmDeleteHistory = false
    @State private var confirmResetCalibration = false
    @State private var confirmResetSettings = false
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
                    systemImage: "record.circle",
                    title: "Motion recordings only if you ask",
                    text: "Diagnostics can record raw head motion for tuning, only when you start it. The file stays on this iPhone unless you share it yourself and is deleted when you leave Diagnostics."
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
                Text("Stored on this iPhone and kept until you delete it. Like other app data, it is included in your iPhone backups. Deleting the app removes everything.")
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
                Button("Reset settings", role: .destructive) {
                    confirmResetSettings = true
                }
                .frame(minHeight: Theme.minimumTapTarget)
                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Manage data")
            } footer: {
                Text(manageDataFooter)
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
        .confirmationDialog("Reset settings?", isPresented: $confirmResetSettings, titleVisibility: .visible) {
            Button("Reset settings", role: .destructive) {
                settings.resetToDefaults()
                statusMessage = "Settings restored to defaults."
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reminder sensitivity, spacing, sound, haptics and demo mode go back to their defaults. Your history and calibration are kept.")
        }
    }

    private var manageDataFooter: String {
        var text = "Each action is separate: deleting history keeps your calibration and settings."
        if controller.sessionState != .idle {
            text += " Deleting history or resetting calibration stops the current session first."
        }
        return text
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
