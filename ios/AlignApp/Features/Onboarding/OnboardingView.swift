import SwiftUI

/// First-run flow: what Align does, privacy & not-medical note, then permissions (F-03).
@MainActor
struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var step = 0
    private let lastStep = 2

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    switch step {
                    case 0:
                        WelcomeStep()
                    case 1:
                        PrivacyStep()
                    default:
                        PermissionsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: Theme.Spacing.s) {
                    Button {
                        if step < lastStep {
                            step += 1
                        } else {
                            onFinish()
                        }
                    } label: {
                        Text(step < lastStep ? "Continue" : "Start using Align")
                            .frame(maxWidth: .infinity, minHeight: Theme.minimumTapTarget - 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    if step > 0 {
                        Button("Back") { step -= 1 }
                            .frame(minHeight: Theme.minimumTapTarget)
                    }
                }
                .padding(Theme.Spacing.m)
                .background(Theme.background)
            }
            .background(Theme.background)
            .toolbar(step == lastStep ? .visible : .hidden, for: .navigationBar)
        }
    }
}

private struct WelcomeStep: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Image(systemName: "airpodspro")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text("Welcome to Align")
                    .font(.largeTitle.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text("Align uses the motion sensors in your AirPods to notice when your head stays tilted forward or to the side for a while, then gives you a gentle nudge to reset.")
                    .font(.body)
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    OnboardingPoint(systemImage: "scope", title: "Calibrate once", text: "Sit comfortably upright for 10 seconds so Align learns your neutral position.")
                    OnboardingPoint(systemImage: "bell", title: "Calm reminders", text: "Short glances down are ignored. You're only reminded after a tilt lasts a while.")
                    OnboardingPoint(systemImage: "chart.bar", title: "See your sessions", text: "Review time in range and reminders over the past week.")
                    OnboardingPoint(systemImage: "iphone", title: "While the app is open", text: "Align monitors while it's open on screen. Leaving the app pauses monitoring.")
                }
            }
            .padding(Theme.Spacing.l)
        }
    }
}

private struct PrivacyStep: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Image(systemName: "hand.raised")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text("Private by design")
                    .font(.largeTitle.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                OnboardingPoint(
                    systemImage: "iphone",
                    title: "Motion stays on your iPhone",
                    text: "Raw head-motion data is processed on device and never saved or uploaded. Align keeps only session summaries, like time in range and reminder counts."
                )
                OnboardingPoint(
                    systemImage: "trash",
                    title: "You're in control",
                    text: "Delete your history or reset calibration any time in Settings › Privacy & data."
                )
                OnboardingPoint(
                    systemImage: "info.circle",
                    title: "A wellness tool, not a medical device",
                    text: "Align encourages posture breaks. It doesn't diagnose, treat or prevent any condition. If you have pain or health concerns, talk to a health professional."
                )
            }
            .padding(Theme.Spacing.l)
        }
    }
}

private struct OnboardingPoint: View {
    let systemImage: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Onboarding") {
    OnboardingView(onFinish: {})
        .appEnvironment(AppEnvironment.preview())
}
