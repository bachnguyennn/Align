import Foundation
import Observation
import AlignCore

/// User-facing toggles persisted as JSON in UserDefaults. Decoding tolerates missing keys so new
/// fields can be added without losing existing settings.
struct AppSettings: Codable, Equatable {
    var remindersEnabled: Bool = true
    var soundEnabled: Bool = true
    var hapticsEnabled: Bool = true
    /// Use `MockSensorProvider` instead of the AirPods (always on in the simulator).
    var demoModeEnabled: Bool = false

    static let storageKey = "align.settings.v1"

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        remindersEnabled = try container.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? true
        soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        hapticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? true
        demoModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .demoModeEnabled) ?? false
    }

    /// Reads the stored settings. Safe to call from any thread (used by the notification delegate).
    static func load(from defaults: UserDefaults) -> AppSettings {
        StoredValue.decode(AppSettings.self, key: storageKey, defaults: defaults) ?? AppSettings()
    }
}

/// Sensitivity presets (F-09). Thresholds apply to forward and lateral tilt; backward tilt
/// (looking up) uses the threshold + 5°. Values are experimental, not medically validated.
enum SensitivityPreset: String, CaseIterable, Identifiable {
    case gentle
    case balanced
    case strict
    case custom

    var id: String { rawValue }

    /// Presets a user can pick directly. `.custom` results from fine-tuning.
    static let selectable: [SensitivityPreset] = [.gentle, .balanced, .strict]

    var title: String {
        switch self {
        case .gentle: return "Gentle"
        case .balanced: return "Balanced"
        case .strict: return "Strict"
        case .custom: return "Custom"
        }
    }

    var thresholdDegrees: Double? {
        switch self {
        case .gentle: return 20
        case .balanced: return 15
        case .strict: return 10
        case .custom: return nil
        }
    }

    var sustainedDuration: TimeInterval? {
        switch self {
        case .gentle: return 60
        case .balanced: return 30
        case .strict: return 20
        case .custom: return nil
        }
    }

    var summary: String {
        guard let threshold = thresholdDegrees, let duration = sustainedDuration else {
            return "Your own angles and hold time."
        }
        return "Past \(Int(threshold))° for \(Int(duration)) seconds"
    }

    /// Returns `configuration` with this preset's thresholds and hold time. Other fields
    /// (cooldown, smoothing, axes, …) are left untouched. `.custom` returns it unchanged.
    func apply(to configuration: PostureConfiguration) -> PostureConfiguration {
        guard let threshold = thresholdDegrees, let duration = sustainedDuration else { return configuration }
        var result = configuration
        result.forwardThresholdDegrees = threshold
        result.lateralThresholdDegrees = threshold
        result.backwardThresholdDegrees = threshold + 5
        result.sustainedDuration = duration
        return result
    }

    /// The preset whose forward/lateral thresholds and hold time match `configuration`, else `.custom`.
    static func matching(_ configuration: PostureConfiguration) -> SensitivityPreset {
        for preset in selectable {
            guard let threshold = preset.thresholdDegrees, let duration = preset.sustainedDuration else { continue }
            if abs(configuration.forwardThresholdDegrees - threshold) < 0.001,
               abs(configuration.lateralThresholdDegrees - threshold) < 0.001,
               abs(configuration.sustainedDuration - duration) < 0.001 {
                return preset
            }
        }
        return .custom
    }
}

/// JSON-in-UserDefaults helpers.
enum StoredValue {
    static func decode<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func encode<T: Encodable>(_ value: T, key: String, defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }
}

/// Settings, detection configuration and the neutral baseline, persisted in UserDefaults.
/// Public properties are computed wrappers over tracked storage so every write is saved.
@MainActor
@Observable
final class SettingsStore {
    enum Keys {
        static let configuration = "align.configuration.v1"
        static let baseline = "align.baseline.v1"
    }

    private var appStorage: AppSettings
    private var configurationStorage: PostureConfiguration
    private var baselineStorage: NeutralBaseline?

    private let defaults: UserDefaults
    /// Called after the detection configuration changes (MonitoringController forwards it to the monitor).
    @ObservationIgnored var onConfigurationChange: ((PostureConfiguration) -> Void)?
    /// Called after demo mode is switched on or off.
    @ObservationIgnored var onDemoModeChange: ((Bool) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.appStorage = AppSettings.load(from: defaults)
        var configuration = StoredValue.decode(PostureConfiguration.self, key: Keys.configuration, defaults: defaults) ?? .default
        // The axis convention is not a user setting; always take the current package default so a
        // stored configuration never freezes an outdated convention (D-011).
        configuration.axes = HeadAxisConvention.airPodsDefault
        self.configurationStorage = configuration
        self.baselineStorage = StoredValue.decode(NeutralBaseline.self, key: Keys.baseline, defaults: defaults)
    }

    var app: AppSettings {
        get { appStorage }
        set {
            guard newValue != appStorage else { return }
            let oldValue = appStorage
            appStorage = newValue
            StoredValue.encode(newValue, key: AppSettings.storageKey, defaults: defaults)
            if newValue.demoModeEnabled != oldValue.demoModeEnabled {
                onDemoModeChange?(newValue.demoModeEnabled)
            }
        }
    }

    var configuration: PostureConfiguration {
        get { configurationStorage }
        set {
            guard newValue != configurationStorage else { return }
            configurationStorage = newValue
            StoredValue.encode(newValue, key: Keys.configuration, defaults: defaults)
            onConfigurationChange?(newValue)
        }
    }

    var baseline: NeutralBaseline? {
        get { baselineStorage }
        set {
            guard newValue != baselineStorage else { return }
            baselineStorage = newValue
            if let newValue {
                StoredValue.encode(newValue, key: Keys.baseline, defaults: defaults)
            } else {
                defaults.removeObject(forKey: Keys.baseline)
            }
        }
    }

    /// Derived from the configuration; setting a selectable preset applies its values.
    var preset: SensitivityPreset {
        get { SensitivityPreset.matching(configuration) }
        set {
            guard newValue != .custom else { return }
            configuration = newValue.apply(to: configuration)
        }
    }

    /// Restores reminder settings, detection configuration and toggles (including demo mode) to
    /// their defaults. The calibration baseline is kept; it has its own reset (D-012).
    func resetToDefaults() {
        var configuration = PostureConfiguration.default
        configuration.axes = HeadAxisConvention.airPodsDefault
        self.configuration = configuration
        app = AppSettings()
    }

    /// Reminder cooldown in whole minutes (UI range 2–30).
    var reminderCooldownMinutes: Int {
        get { Int((configuration.reminderCooldown / 60).rounded()) }
        set { configuration.reminderCooldown = TimeInterval(newValue) * 60 }
    }
}
