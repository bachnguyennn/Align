import XCTest
import AlignCore
@testable import Align

final class SensitivityPresetTests: XCTestCase {
    func testPresetValues() {
        let gentle = SensitivityPreset.gentle.apply(to: .default)
        XCTAssertEqual(gentle.forwardThresholdDegrees, 20)
        XCTAssertEqual(gentle.lateralThresholdDegrees, 20)
        XCTAssertEqual(gentle.backwardThresholdDegrees, 25)
        XCTAssertEqual(gentle.sustainedDuration, 60)

        let balanced = SensitivityPreset.balanced.apply(to: .default)
        XCTAssertEqual(balanced.forwardThresholdDegrees, 15)
        XCTAssertEqual(balanced.lateralThresholdDegrees, 15)
        XCTAssertEqual(balanced.sustainedDuration, 30)

        let strict = SensitivityPreset.strict.apply(to: .default)
        XCTAssertEqual(strict.forwardThresholdDegrees, 10)
        XCTAssertEqual(strict.lateralThresholdDegrees, 10)
        XCTAssertEqual(strict.sustainedDuration, 20)
    }

    func testBalancedMatchesPackageDefault() {
        XCTAssertEqual(SensitivityPreset.matching(.default), .balanced)
        XCTAssertEqual(SensitivityPreset.balanced.apply(to: .default), .default)
    }

    func testApplyKeepsOtherFields() {
        var configuration = PostureConfiguration.default
        configuration.reminderCooldown = 600
        configuration.hysteresisDegrees = 4
        let strict = SensitivityPreset.strict.apply(to: configuration)
        XCTAssertEqual(strict.reminderCooldown, 600)
        XCTAssertEqual(strict.hysteresisDegrees, 4)
        XCTAssertEqual(strict.axes, configuration.axes)
    }

    func testMatchingRoundTripsEverySelectablePreset() {
        for preset in SensitivityPreset.selectable {
            XCTAssertEqual(SensitivityPreset.matching(preset.apply(to: .default)), preset)
        }
    }

    func testCustomValuesAreDetected() {
        var configuration = SensitivityPreset.gentle.apply(to: .default)
        configuration.forwardThresholdDegrees = 18
        XCTAssertEqual(SensitivityPreset.matching(configuration), .custom)
        XCTAssertEqual(SensitivityPreset.custom.apply(to: configuration), configuration)
    }
}

final class AppSettingsTests: XCTestCase {
    func testDecodingToleratesMissingKeys() throws {
        let data = Data(#"{"soundEnabled": false}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertFalse(settings.soundEnabled)
        XCTAssertTrue(settings.remindersEnabled)
        XCTAssertTrue(settings.hapticsEnabled)
        XCTAssertFalse(settings.demoModeEnabled)
    }

    func testRoundTrip() throws {
        var settings = AppSettings()
        settings.demoModeEnabled = true
        settings.hapticsEnabled = false
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
    }

    @MainActor
    func testSettingsStorePersistsConfigurationAndBaseline() {
        let suite = "align.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.preset, .balanced)
        store.preset = .strict
        store.reminderCooldownMinutes = 10
        store.baseline = NeutralBaseline(gravity: Vector3(x: 0, y: 0, z: -1), capturedAt: Date(timeIntervalSince1970: 1_000), sampleCount: 250, version: 3)
        store.app.soundEnabled = false

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.preset, .strict)
        XCTAssertEqual(reloaded.configuration.reminderCooldown, 600)
        XCTAssertEqual(reloaded.reminderCooldownMinutes, 10)
        XCTAssertEqual(reloaded.baseline?.version, 3)
        XCTAssertFalse(reloaded.app.soundEnabled)

        store.baseline = nil
        XCTAssertNil(SettingsStore(defaults: defaults).baseline)
    }

    @MainActor
    func testResetToDefaultsKeepsBaseline() {
        let suite = "align.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(defaults: defaults)
        store.preset = .strict
        store.app.hapticsEnabled = false
        store.baseline = NeutralBaseline(gravity: Vector3(x: 0, y: 0, z: -1), capturedAt: Date(), sampleCount: 250, version: 1)
        store.resetToDefaults()
        XCTAssertEqual(store.preset, .balanced)
        XCTAssertTrue(store.app.hapticsEnabled)
        XCTAssertNotNil(store.baseline)
    }

    @MainActor
    func testStoredAxesAreReplacedByPackageDefault() throws {
        let suite = "align.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var stale = PostureConfiguration.default
        stale.axes = HeadAxisConvention(forwardAxis: Vector3(x: 0, y: 0, z: 1), lateralAxis: Vector3(x: 0, y: 1, z: 0))
        defaults.set(try JSONEncoder().encode(stale), forKey: SettingsStore.Keys.configuration)
        XCTAssertEqual(SettingsStore(defaults: defaults).configuration.axes, HeadAxisConvention.airPodsDefault)
    }

    @MainActor
    func testConfigurationChangeCallbackFires() {
        let suite = "align.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(defaults: defaults)
        var received: PostureConfiguration?
        store.onConfigurationChange = { received = $0 }
        store.preset = .gentle
        XCTAssertEqual(received?.forwardThresholdDegrees, 20)
    }
}

final class FormatTests: XCTestCase {
    func testDuration() {
        XCTAssertEqual(Format.duration(0), "0 s")
        XCTAssertEqual(Format.duration(44.6), "45 s")
        XCTAssertEqual(Format.duration(60), "1 min")
        XCTAssertEqual(Format.duration(59 * 60 + 59), "59 min")
        XCTAssertEqual(Format.duration(3600), "1 h")
        XCTAssertEqual(Format.duration(3600 + 5 * 60), "1 h 5 min")
        XCTAssertEqual(Format.duration(-5), "0 s")
    }

    func testSpokenTilt() {
        XCTAssertEqual(Format.spokenTilt(forward: 18.2, lateral: 0.3), "Head tilted 18 degrees forward")
        XCTAssertEqual(Format.spokenTilt(forward: -1, lateral: 2), "Head tilted 1 degree back and 2 degrees to the right")
        XCTAssertEqual(Format.spokenTilt(forward: 0.2, lateral: -0.4), "Head level with your neutral position")
    }

    func testTiltSummary() {
        XCTAssertEqual(Format.tiltSummary(forward: 18, lateral: -3), "18° forward · 3° left")
        XCTAssertEqual(Format.tiltSummary(forward: 0, lateral: 0), "Level")
    }
}

final class AxisCheckTests: XCTestCase {
    private let degree = Double.pi / 180

    /// Gravity seen in the head frame after the head rotates by `angle` about `axis`.
    private func gravityAfterHeadRotation(_ neutral: Vector3, axis: Vector3, degrees: Double) -> Vector3 {
        Quaternion(axis: axis, angleRadians: -degrees * degree).rotate(neutral)
    }

    func testForwardRotationGivesPositiveForward() throws {
        let axes = HeadAxisConvention.airPodsDefault
        let neutral = Vector3(x: 0, y: 0, z: -1)
        let current = gravityAfterHeadRotation(neutral, axis: axes.forwardAxis, degrees: 20)
        let result = try XCTUnwrap(AxisCheck.tilt(neutralGravity: neutral, currentGravity: current, axes: axes))
        XCTAssertEqual(result.forwardDegrees, 20, accuracy: 1e-6)
        XCTAssertEqual(result.lateralDegrees, 0, accuracy: 1e-6)
        XCTAssertEqual(result.totalDegrees, 20, accuracy: 1e-6)
    }

    func testLateralRotationGivesPositiveLateral() throws {
        let axes = HeadAxisConvention.airPodsDefault
        let neutral = Vector3(x: 0, y: 0, z: -1)
        let current = gravityAfterHeadRotation(neutral, axis: axes.lateralAxis, degrees: 12)
        let result = try XCTUnwrap(AxisCheck.tilt(neutralGravity: neutral, currentGravity: current, axes: axes))
        XCTAssertEqual(result.lateralDegrees, 12, accuracy: 1e-6)
        XCTAssertEqual(result.forwardDegrees, 0, accuracy: 1e-6)
    }

    func testNoRotationIsZero() throws {
        let neutral = Vector3(x: 0.1, y: 0, z: -0.99)
        let result = try XCTUnwrap(AxisCheck.tilt(neutralGravity: neutral, currentGravity: neutral, axes: .airPodsDefault))
        XCTAssertEqual(result.totalDegrees, 0, accuracy: 1e-9)
    }
}
