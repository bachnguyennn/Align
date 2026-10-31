import SwiftUI
import AlignCore

/// Settings tab: reminders, calibration, device & permissions, privacy, diagnostics (F-09).
@MainActor
struct SettingsView: View {
    @Environment(MonitoringController.self) private var controller
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ReminderSettingsView()
                    } label: {
                        LabeledContent {
                            Text(reminderSummary)
                        } label: {
                            Label("Reminders", systemImage: "bell")
                        }
                    }
                }

                Section {
                    NavigationLink {
                        CalibrationView()
                    } label: {
                        LabeledContent {
                            Text(calibrationSummary)
                        } label: {
                            Label("Neutral position", systemImage: "scope")
                        }
                    }
                    if controller.baseline != nil {
                        // Redo nod / Use default axes live on the Neutral position screen.
                        LabeledContent {
                            Text(HeadAxisConvention.sourceTitle(learned: controller.hasLearnedAxes))
                        } label: {
                            Label("Tilt axes", systemImage: "arrow.up.and.down")
                        }
                    }
                    NavigationLink {
                        PermissionsView()
                    } label: {
                        Label("AirPods & permissions", systemImage: "airpodspro")
                    }
                } header: {
                    Text("Posture")
                }

                Section {
                    NavigationLink {
                        PrivacyDataView()
                    } label: {
                        Label("Privacy & data", systemImage: "hand.raised")
                    }
                }

                Section {
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        Label("Diagnostics", systemImage: "wrench.and.screwdriver")
                    }
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Live sensor values for checking your AirPods and the tilt axes, and an optional motion recording you can share for tuning.")
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                } header: {
                    Text("About")
                } footer: {
                    Text("Align is a wellness tool that encourages posture breaks. It is not a medical device and does not diagnose, treat or prevent any condition.")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var reminderSummary: String {
        guard settings.app.remindersEnabled else { return "Off" }
        return settings.preset.title
    }

    private var calibrationSummary: String {
        guard let baseline = controller.baseline else { return "Not set" }
        return baseline.capturedAt.formatted(date: .abbreviated, time: .omitted)
    }

    private var appVersion: String {
        AppInfo.versionString
    }
}

/// Sensitivity presets, fine-tuning, cooldown and delivery toggles (F-09).
@MainActor
struct ReminderSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle("Posture reminders", isOn: $settings.app.remindersEnabled)
            } footer: {
                Text("Align sends a gentle notification when your head stays tilted past your angles for the hold time.")
            }

            Section {
                ForEach(SensitivityPreset.selectable) { preset in
                    presetRow(preset)
                }
                if settings.preset == .custom {
                    Label("Custom values in use", systemImage: "slider.horizontal.3")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Sensitivity")
            }

            Section {
                Stepper(value: $settings.configuration.forwardThresholdDegrees, in: 5...30, step: 1) {
                    LabeledContent("Forward tilt", value: "\(Int(settings.configuration.forwardThresholdDegrees))°")
                }
                Stepper(value: $settings.configuration.lateralThresholdDegrees, in: 5...30, step: 1) {
                    LabeledContent("Sideways tilt", value: "\(Int(settings.configuration.lateralThresholdDegrees))°")
                }
                Stepper(value: $settings.configuration.sustainedDuration, in: 10...120, step: 5) {
                    LabeledContent("Hold time", value: "\(Int(settings.configuration.sustainedDuration)) s")
                }
            } header: {
                Text("Fine-tune")
            } footer: {
                Text("Angles are measured from your calibrated neutral position. These values are a starting point, not medical guidance.")
            }

            Section {
                Stepper(value: $settings.reminderCooldownMinutes, in: 2...30) {
                    LabeledContent("At most every", value: "\(settings.reminderCooldownMinutes) min")
                }
            } header: {
                Text("Spacing")
            } footer: {
                Text("You won't get more than one reminder per tilt, and never more often than this.")
            }

            Section {
                Toggle("Sound", isOn: $settings.app.soundEnabled)
                Toggle("Haptics", isOn: $settings.app.hapticsEnabled)
            } header: {
                Text("Delivery")
            } footer: {
                Text("Haptics play when Align is open. Notification sound also follows your iPhone's Focus and silent settings.")
            }
            .disabled(!settings.app.remindersEnabled)
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func presetRow(_ preset: SensitivityPreset) -> some View {
        let isSelected = settings.preset == preset
        return Button {
            settings.preset = preset
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.title)
                        .foregroundStyle(.primary)
                    Text(preset.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: Theme.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Settings") {
    SettingsView()
        .appEnvironment(AppEnvironment.preview())
}
