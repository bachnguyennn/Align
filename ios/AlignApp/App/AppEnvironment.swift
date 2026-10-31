import Foundation
import SwiftData
import AlignCore
import Sensors

/// Builds and owns the app's long-lived objects.
@MainActor
final class AppEnvironment {
    let modelContainer: ModelContainer
    let settings: SettingsStore
    let notifier: ReminderNotifier
    let sessionStore: SessionStore
    let controller: MonitoringController

    init(inMemory: Bool = false, defaults: UserDefaults = .standard) {
        let container = AppEnvironment.makeContainer(inMemory: inMemory)
        let settings = SettingsStore(defaults: defaults)
        let notifier = ReminderNotifier()
        let sessionStore = SessionStore(context: container.mainContext)
        let controller = MonitoringController(
            settings: settings,
            notifier: notifier,
            store: sessionStore,
            makeProvider: { demoMode in AppEnvironment.makeProvider(demoMode: demoMode) }
        )
        self.modelContainer = container
        self.settings = settings
        self.notifier = notifier
        self.sessionStore = sessionStore
        self.controller = controller
        sessionStore.closeUnfinishedSessions()
        // A diagnostic recording left behind if the app was terminated mid-share (D-017 (d)).
        MotionRecorder.removeFiles()
    }

    /// Real AirPods on device; the deterministic mock in the simulator or in demo mode.
    static func makeProvider(demoMode: Bool) -> any SensorProvider {
        #if targetEnvironment(simulator)
        return MockSensorProvider(scenario: .manual)
        #else
        if demoMode {
            return MockSensorProvider(scenario: .manual)
        }
        return RealAirPodsSensorProvider()
        #endif
    }

    private static func makeContainer(inMemory: Bool) -> ModelContainer {
        let schema = Schema([MonitoringSession.self, PostureEvent.self])
        // Local only: no CloudKit, data stays on this device.
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            Log.persistence.error("Opening the store failed, using memory only: \(error.localizedDescription, privacy: .public)")
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            do {
                return try ModelContainer(for: schema, configurations: [fallback])
            } catch {
                fatalError("Could not create a SwiftData container: \(error)")
            }
        }
    }

    /// In-memory environment with the mock sensor, for SwiftUI previews.
    static func preview() -> AppEnvironment {
        let defaults = UserDefaults(suiteName: "align.preview") ?? .standard
        return AppEnvironment(inMemory: true, defaults: defaults)
    }
}
