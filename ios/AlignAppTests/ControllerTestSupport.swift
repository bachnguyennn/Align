import Foundation
import XCTest
import AlignCore
@testable import Align

/// Noise-free head poses, same model as `Pose` in the AlignKit tests and the Java reference:
/// attitude = Tilt(rotation vector forward·forwardAxis + lateral·lateralAxis) · Mount(yaw about
/// the head's up axis, lateral × forward). Heading is fixed; it never affects tilt.
enum TestPose {
    static let rad = Double.pi / 180
    static let down = Vector3(x: 0, y: 0, z: -1)

    static func attitude(forward: Double, lateral: Double, mountYaw: Double = 0, axes: HeadAxisConvention = .airPodsDefault) -> Quaternion {
        let rv = axes.forwardAxis * (forward * rad) + axes.lateralAxis * (lateral * rad)
        let tilt = rv.length == 0 ? Quaternion.identity : Quaternion(axis: rv, angleRadians: rv.length)
        var mount = Quaternion.identity
        if mountYaw != 0 {
            let headUp = axes.lateralAxis.cross(axes.forwardAxis)
            mount = Quaternion(axis: headUp, angleRadians: mountYaw * rad)
        }
        return (tilt * mount).normalized
    }

    static func sample(_ t: TimeInterval, forward: Double = 0, lateral: Double = 0, mountYaw: Double = 0) -> MotionSample {
        let q = attitude(forward: forward, lateral: lateral, mountYaw: mountYaw)
        return MotionSample(timestamp: t, attitude: q, gravity: q.conjugate.rotate(down))
    }
}

/// A clock the tests advance by hand (monotonic seconds).
final class TestClock {
    var now: TimeInterval = 1_000
}

/// `WatchdogTimer` whose ticks the tests fire by hand.
@MainActor
final class ManualWatchdogTimer: WatchdogTimer {
    private(set) var isRunning = false
    private(set) var startCount = 0
    private var tick: (@MainActor () -> Void)?

    func start(interval: TimeInterval, tick: @escaping @MainActor () -> Void) {
        isRunning = true
        startCount += 1
        self.tick = tick
    }

    func stop() {
        isRunning = false
        tick = nil
    }

    func fire() {
        tick?()
    }
}

/// A `MonitoringController` over an in-memory environment and the mock sensor, with a manual
/// watchdog timer, a manual clock and a private recordings folder. Events are fed straight into
/// `handle(_:)`, so nothing depends on real time. Call `finish()` at the end of each test.
@MainActor
final class ControllerHarness {
    let suite: String
    let defaults: UserDefaults
    let environment: AppEnvironment
    let clock: TestClock
    let timer: ManualWatchdogTimer
    let recordingDirectory: URL
    let controller: MonitoringController
    /// Earbud yaw in the ear for generated samples (degrees).
    var mountYaw: Double = 0

    static let rate: Double = 25

    init() {
        let suite = "align.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let environment = AppEnvironment(inMemory: true, defaults: defaults)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("align-tests-\(UUID().uuidString)", isDirectory: true)
        let clock = TestClock()
        let timer = ManualWatchdogTimer()
        let watchdog = SampleWatchdog(timer: timer, clock: { clock.now })
        let recorder = MotionRecorder(directory: directory, clock: { clock.now })
        let controller = MonitoringController(
            settings: environment.settings,
            notifier: environment.notifier,
            store: environment.sessionStore,
            makeProvider: { demoMode in AppEnvironment.makeProvider(demoMode: demoMode) },
            sampleWatchdog: watchdog,
            recorder: recorder
        )
        self.suite = suite
        self.defaults = defaults
        self.environment = environment
        self.recordingDirectory = directory
        self.clock = clock
        self.timer = timer
        self.controller = controller
        // No notifications from the test host.
        environment.settings.app.remindersEnabled = false
    }

    /// Starts streaming (as an open Diagnostics screen does) and reports the AirPods connected.
    func connect() {
        controller.acquireSensor(.diagnostics)
        controller.handle(.connectionChanged(.connected))
    }

    /// Feeds `seconds` of samples at 25 Hz, advancing the clock, and fires the watchdog after
    /// each one (as its timer would while samples flow).
    func feed(seconds: Double, pose: (Double) -> (forward: Double, lateral: Double) = { _ in (0, 0) }) {
        let count = Int((seconds * ControllerHarness.rate).rounded())
        for i in 0..<count {
            clock.now += 1 / ControllerHarness.rate
            let p = pose(Double(i) / ControllerHarness.rate)
            controller.handle(.sample(TestPose.sample(clock.now, forward: p.forward, lateral: p.lateral, mountYaw: mountYaw)))
            timer.fire()
        }
    }

    /// Runs a neutral calibration from upright samples and checks it succeeded.
    func calibrateNeutral(file: StaticString = #filePath, line: UInt = #line) {
        controller.startCalibration()
        feed(seconds: 10.4)
        guard case .succeeded = controller.calibrationPhase else {
            XCTFail("neutral calibration did not succeed: \(controller.calibrationPhase)", file: file, line: line)
            return
        }
    }

    /// One slow nod: 1 s down to `depth`, 1 s back up, then 2 s neutral.
    func nod(depth: Double = 25) {
        feed(seconds: 4) { rel in
            if rel < 1 {
                return (depth * rel, 0)
            }
            if rel < 2 {
                return (depth * (2 - rel), 0)
            }
            return (0, 0)
        }
    }

    /// The baseline as a fresh launch would load it from UserDefaults.
    var reloadedBaseline: NeutralBaseline? {
        SettingsStore(defaults: defaults).baseline
    }

    func finish() {
        controller.discardRecording()
        if controller.sessionState != .idle {
            controller.stopSession()
        }
        controller.cancelCalibration()
        for client in [SensorClient.diagnostics, .calibration, .session] {
            controller.releaseSensor(client)
        }
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: recordingDirectory)
    }
}
