import SwiftUI
import SwiftData

@main
@MainActor
struct AlignApp: App {
    private let environment: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase

    init() {
        environment = AppEnvironment()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .appEnvironment(environment)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Foreground-only MVP (D-010): leaving .active pauses monitoring; going to the
            // background also stops the sensor.
            switch newPhase {
            case .active:
                environment.controller.appDidBecomeActive()
            case .background:
                environment.controller.appDidLeaveForeground(stopSensor: true)
            default:
                environment.controller.appDidLeaveForeground(stopSensor: false)
            }
        }
    }
}

enum StorageKeys {
    static let hasCompletedOnboarding = "align.hasCompletedOnboarding"
}

/// Onboarding gate, then the main tabs.
@MainActor
struct RootView: View {
    @AppStorage(StorageKeys.hasCompletedOnboarding) private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingView(onFinish: { hasCompletedOnboarding = true })
            }
        }
    }
}

@MainActor
struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Home", systemImage: "house") }
            HistoryView()
                .tabItem { Label("History", systemImage: "chart.bar") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

extension View {
    /// Injects the app's observable objects and the SwiftData container.
    @MainActor
    func appEnvironment(_ environment: AppEnvironment) -> some View {
        self
            .environment(environment.controller)
            .environment(environment.settings)
            .environment(environment.notifier)
            .modelContainer(environment.modelContainer)
            .tint(Theme.accent)
    }
}

#Preview("Root") {
    RootView()
        .appEnvironment(AppEnvironment.preview())
}
