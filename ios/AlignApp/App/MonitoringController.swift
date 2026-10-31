import Foundation
import Observation
import AlignCore
import PostureDetection
import Sensors

enum SessionState: String, Equatable {
    case idle
    case running
    case paused
}

/// Reasons the sensor stream is needed. Streaming runs while at least one client holds it.
/// Why a session is paused.
enum PauseReason: Equatable {
    case user
    /// The app left the foreground. Align monitors only while it is open (D-010).
    case appInactive
}

enum SensorClient: Hashable {
    case dashboard
    case liveView
    case calibration
    case diagnostics
    case permissions
    case session
}

enum CalibrationPhase: Equatable {
    case idle
    /// Calibration requested, waiting for samples (e.g. AirPods not connected yet).
    case waitingForSensor
    case inProgress(progress: Double)
    case succeeded(NeutralBaseline)
    case failed(CalibrationFailure)
}

enum SensorSource: Equatable {
    case airPods
    case demo
}

enum BuildEnvironment {
    static let isSimulator: Bool = {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }()
}

/// Owns the sensor provider and the posture monitor, runs the session lifecycle, does the time
/// accounting and writes sessions/events to SwiftData. All UI reads go through this object.
@MainActor
@Observable
final class MonitoringController {
    // MARK: Observed state

    private(set) var connectionState: SensorConnectionState = .idle
    private(set) var authorization: SensorAuthorization = .notDetermined
    private(set) var isMotionAvailable = false
    private(set) var sensorSource: SensorSource = .airPods
    private(set) var isStreaming = false
    /// Latest raw sample, for Diagnostics only. Never persisted.
    private(set) var latestSample: MotionSample? = nil
    private(set) var rateMeter = SampleRateMeter()
    private(set) var latestTilt: TiltEstimate? = nil
    private(set) var postureState: PostureState = .unavailable
    private(set) var sessionState: SessionState = .idle
    private(set) var sessionStartedAt: Date? = nil
    private(set) var pauseReason: PauseReason? = nil
    private(set) var accumulator = SessionAccumulator()
    /// Totals of the most recently finished session, shown on the dashboard.
    private(set) var lastFinishedSession: SessionAccumulator? = nil
    private(set) var lastReminderAt: Date? = nil
    private(set) var calibrationPhase: CalibrationPhase = .idle

    private var demoScenarioStorage: MockScenario = .manual
    private var demoForwardStorage: Double = 0
    private var demoLateralStorage: Double = 0

    // MARK: Dependencies and internals

    let settings: SettingsStore
    private let notifier: ReminderNotifier
    private let store: SessionStore
    private let makeProvider: @MainActor (Bool) -> any SensorProvider

    @ObservationIgnored private var provider: any SensorProvider
    @ObservationIgnored private var monitor: PostureMonitor
    @ObservationIgnored private var streamTask: Task<Void, Never>? = nil
    @ObservationIgnored private var streamGeneration = 0
    @ObservationIgnored private var clients: Set<SensorClient> = []
    @ObservationIgnored private var activeSession: MonitoringSession? = nil
    @ObservationIgnored private var lastSampleTimestamp: TimeInterval? = nil
    @ObservationIgnored private var lastPersistTimestamp: TimeInterval? = nil
    @ObservationIgnored private var suppressedReminderWhileInactive = false

    /// How often running-session totals are written to SwiftData (seconds of sample time).
    private static let persistInterval: TimeInterval = 15

    /// - Parameter makeProvider: builds the sensor provider; the argument is the demo-mode flag.
    init(
        settings: SettingsStore,
        notifier: ReminderNotifier,
        store: SessionStore,
        makeProvider: @escaping @MainActor (Bool) -> any SensorProvider
    ) {
        self.settings = settings
        self.notifier = notifier
        self.store = store
        self.makeProvider = makeProvider
        let initialProvider = makeProvider(settings.app.demoModeEnabled)
        self.provider = initialProvider
        let initialMonitor = PostureMonitor(configuration: settings.configuration, baseline: settings.baseline)
        self.monitor = initialMonitor
        self.sensorSource = initialProvider is MockSensorProvider ? .demo : .airPods
        self.postureState = initialMonitor.state

        refreshProviderStatus()
        settings.onConfigurationChange = { [weak self] configuration in
            self?.monitor.configuration = configuration
        }
        settings.onDemoModeChange = { [weak self] enabled in
            self?.switchProvider(demoMode: enabled)
        }
    }

    // MARK: Derived state

    var baseline: NeutralBaseline? { settings.baseline }

    var isCalibrating: Bool {
        switch calibrationPhase {
        case .waitingForSensor, .inProgress:
            return true
        case .idle, .succeeded, .failed:
            return false
        }
    }

    var canStartSession: Bool {
        sessionState == .idle && baseline != nil && !isCalibrating
    }

    /// Whether the current tilt is past a threshold (deviating or sustained).
    var isOutsideRange: Bool {
        switch postureState {
        case .deviating, .sustainedTilt:
            return true
        default:
            return false
        }
    }

    // MARK: Demo sensor controls

    var demoScenario: MockScenario {
        get { demoScenarioStorage }
        set {
            demoScenarioStorage = newValue
            mockProvider?.scenario = newValue
        }
    }

    var demoForwardDegrees: Double {
        get { demoForwardStorage }
        set {
            demoForwardStorage = newValue
            pushDemoTilt()
        }
    }

    var demoLateralDegrees: Double {
        get { demoLateralStorage }
        set {
            demoLateralStorage = newValue
            pushDemoTilt()
        }
    }

    func resetDemoTilt() {
        demoForwardStorage = 0
        demoLateralStorage = 0
        pushDemoTilt()
    }

    private var mockProvider: MockSensorProvider? {
        provider as? MockSensorProvider
    }

    private func pushDemoTilt() {
        mockProvider?.setSimulatedTilt(forwardDegrees: demoForwardStorage, lateralDegrees: demoLateralStorage)
    }

    // MARK: Sensor clients

    func acquireSensor(_ client: SensorClient) {
        clients.insert(client)
        startStreamingIfNeeded()
    }

    func releaseSensor(_ client: SensorClient) {
        clients.remove(client)
        if clients.isEmpty {
            stopStreaming()
        }
    }

    // MARK: Session lifecycle

    func startSession() {
        guard canStartSession, let baseline else { return }
        acquireSensor(.session)
        restartDetection(resetCooldown: true)
        accumulator = SessionAccumulator()
        lastFinishedSession = nil
        lastReminderAt = nil
        lastPersistTimestamp = nil
        let now = Date()
        sessionStartedAt = now
        activeSession = store.startSession(
            startedAt: now,
            calibrationVersion: baseline.version,
            status: sensorSource == .demo ? .mock : .real
        )
        sessionState = .running
    }

    func pauseSession() {
        pauseSession(reason: .user)
    }

    private func pauseSession(reason: PauseReason) {
        guard sessionState == .running else { return }
        // Interrupt while still running so an open episode is persisted with this session.
        interruptMonitor()
        sessionState = .paused
        pauseReason = reason
        suppressedReminderWhileInactive = false
        syncActiveSession()
        store.save()
        releaseSensor(.session)
    }

    func resumeSession() {
        guard sessionState == .paused, !isCalibrating else { return }
        acquireSensor(.session)
        // Samples seen while paused must not count toward a sustained tilt.
        restartDetection(resetCooldown: suppressedReminderWhileInactive)
        accumulator.breakContinuity()
        pauseReason = nil
        sessionState = .running
    }

    func stopSession() {
        guard sessionState != .idle else { return }
        if sessionState == .running {
            interruptMonitor()
        }
        sessionState = .idle
        pauseReason = nil
        if let session = activeSession {
            syncActiveSession()
            session.endedAt = Date()
            if accumulator.monitoredSeconds == 0, case .unavailable = connectionState {
                session.sensorAvailabilityStatus = SensorAvailabilityStatus.unavailable.rawValue
            }
            store.save()
        }
        lastFinishedSession = accumulator
        activeSession = nil
        sessionStartedAt = nil
        releaseSensor(.session)
    }

    // MARK: Calibration

    func startCalibration() {
        if sessionState == .running {
            pauseSession()
        }
        acquireSensor(.calibration)
        monitor.beginCalibration()
        calibrationPhase = connectionState == .connected ? .inProgress(progress: 0) : .waitingForSensor
    }

    func cancelCalibration() {
        guard isCalibrating else { return }
        monitor.cancelCalibration()
        calibrationPhase = .idle
        postureState = monitor.state
    }

    /// Clears a finished calibration result so the screen shows its instructions again.
    func acknowledgeCalibrationResult() {
        if !isCalibrating {
            calibrationPhase = .idle
        }
    }

    /// Deletes the stored baseline. Any session is stopped first.
    func resetCalibration() {
        if sessionState != .idle {
            stopSession()
        }
        if isCalibrating {
            monitor.cancelCalibration()
        }
        settings.baseline = nil
        monitor = PostureMonitor(configuration: settings.configuration, baseline: nil)
        latestTilt = nil
        postureState = monitor.state
        calibrationPhase = .idle
    }

    // MARK: Data management

    func deleteAllHistory() {
        if sessionState != .idle {
            stopSession()
        }
        store.deleteAllHistory()
        lastFinishedSession = nil
    }

    // MARK: App lifecycle

    /// The app left `.active`. MVP is foreground-only (D-010): a running session is paused (the
    /// monitor is interrupted so open episodes close) and totals are saved.
    ///
    /// - Parameter stopSensor: true for `.background`, which also stops the provider. For
    ///   `.inactive` the provider keeps running for screens that still hold it, because system
    ///   alerts (including the Motion & Fitness prompt itself) make the app briefly inactive.
    ///   Clients are kept either way so streaming restarts on return.
    func appDidLeaveForeground(stopSensor: Bool) {
        if sessionState == .running {
            pauseSession(reason: .appInactive)
        }
        syncActiveSession()
        store.save()
        if stopSensor {
            if isCalibrating {
                // Don't report a background transition as a sensor failure.
                monitor.cancelCalibration()
                calibrationPhase = .idle
            }
            stopStreaming()
            postureState = monitor.state
        }
    }

    /// The app is `.active` again: restart streaming for the visible screens and resume a session
    /// that was paused only because the app left the foreground.
    func appDidBecomeActive() {
        refreshProviderStatus()
        if !clients.isEmpty {
            startStreamingIfNeeded()
        }
        if sessionState == .paused, pauseReason == .appInactive {
            resumeSession()
        }
    }

    func refreshProviderStatus() {
        authorization = provider.authorization
        isMotionAvailable = provider.isMotionAvailable
    }

    // MARK: Streaming

    private func startStreamingIfNeeded() {
        guard !isStreaming else { return }
        isStreaming = true
        streamGeneration += 1
        let generation = streamGeneration
        rateMeter = SampleRateMeter()
        lastSampleTimestamp = nil
        if let mock = mockProvider {
            if mock.scenario != demoScenarioStorage {
                mock.scenario = demoScenarioStorage
            }
            pushDemoTilt()
        }
        let stream = provider.start()
        streamTask = Task { [weak self] in
            for await event in stream {
                guard let self = self, self.streamGeneration == generation else { break }
                self.handle(event)
            }
        }
    }

    private func stopStreaming() {
        guard isStreaming else { return }
        isStreaming = false
        streamGeneration += 1
        streamTask?.cancel()
        streamTask = nil
        provider.stop()
        interruptMonitor()
        connectionState = .idle
        latestSample = nil
        latestTilt = nil
        refreshProviderStatus()
    }

    private func switchProvider(demoMode: Bool) {
        let wantsMock = demoMode || BuildEnvironment.isSimulator
        guard (provider is MockSensorProvider) != wantsMock else { return }
        // Don't mix real and simulated data within one session.
        if sessionState != .idle {
            stopSession()
        }
        if isCalibrating {
            cancelCalibration()
        }
        stopStreaming()
        provider = makeProvider(demoMode)
        sensorSource = provider is MockSensorProvider ? .demo : .airPods
        connectionState = .idle
        refreshProviderStatus()
        if !clients.isEmpty {
            startStreamingIfNeeded()
        }
    }

    private func handle(_ event: SensorEvent) {
        switch event {
        case .connectionChanged(let state):
            let wasConnected = connectionState == .connected
            if connectionState != state {
                connectionState = state
            }
            refreshProviderStatus()
            // Interrupt on any move away from a streaming state (.waitingForHeadphones, .failed,
            // .idle, .unavailable) so open episodes close and timers reset.
            if state != .connected && (wasConnected || lastSampleTimestamp != nil) {
                interruptMonitor()
                lastSampleTimestamp = nil
                latestTilt = nil
                latestSample = nil
            }
        case .sample(let sample):
            latestSample = sample
            rateMeter.record(sample.timestamp)
            lastSampleTimestamp = sample.timestamp
            let update = monitor.process(sample)
            apply(update, fromSample: true)
        }
    }

    // MARK: Posture updates

    private func interruptMonitor() {
        let timestamp = lastSampleTimestamp ?? ProcessInfo.processInfo.systemUptime
        let update = monitor.interrupt(at: timestamp)
        apply(update, fromSample: false)
    }

    /// Resets the monitor's deviation timers without failing a calibration in progress.
    /// Call before switching `sessionState` to `.running`, so anything it closes is ignored.
    private func restartDetection(resetCooldown: Bool) {
        if !isCalibrating {
            interruptMonitor()
        }
        if resetCooldown {
            monitor.resetCooldown()
        }
        suppressedReminderWhileInactive = false
    }

    private func apply(_ update: PostureUpdate, fromSample: Bool) {
        if postureState != update.state {
            postureState = update.state
        }
        latestTilt = update.tilt

        if sessionState == .running {
            if fromSample {
                accumulator.record(state: update.state, at: update.timestamp, maxStep: monitor.configuration.maxSampleGap)
            } else {
                accumulator.breakContinuity()
            }
            if let reminder = update.reminder {
                deliverReminder(reminder)
            }
            if let episode = update.completedEpisode {
                persist(episode)
            }
            if fromSample {
                persistProgressIfDue(at: update.timestamp)
            }
        } else if update.reminder != nil {
            // The monitor started its cooldown for a reminder we did not deliver.
            suppressedReminderWhileInactive = true
        }

        if let outcome = update.calibrationOutcome {
            handleCalibrationOutcome(outcome)
        } else if case .calibrating(let progress) = update.state, isCalibrating {
            calibrationPhase = .inProgress(progress: progress)
        }
    }

    private func handleCalibrationOutcome(_ outcome: CalibrationOutcome) {
        switch outcome {
        case .succeeded(let newBaseline):
            settings.baseline = newBaseline
            calibrationPhase = .succeeded(newBaseline)
            if let session = activeSession {
                session.calibrationVersion = newBaseline.version
                store.save()
            }
        case .failed(let reason):
            calibrationPhase = .failed(reason)
        }
    }

    private func deliverReminder(_ reminder: ReminderDecision) {
        guard settings.app.remindersEnabled else { return }
        accumulator.recordReminder()
        lastReminderAt = Date()
        notifier.deliver(reminder, settings: settings.app)
        syncActiveSession()
        store.save()
    }

    private func persist(_ episode: PostureEpisode) {
        guard let session = activeSession else { return }
        store.addEvent(
            from: episode,
            reminderTriggered: episode.reminderTriggered && settings.app.remindersEnabled,
            to: session,
            clock: MonotonicClock.now()
        )
    }

    private func persistProgressIfDue(at timestamp: TimeInterval) {
        guard let last = lastPersistTimestamp else {
            lastPersistTimestamp = timestamp
            return
        }
        if timestamp - last >= MonitoringController.persistInterval || timestamp < last {
            lastPersistTimestamp = timestamp
            syncActiveSession()
            store.save()
        }
    }

    private func syncActiveSession() {
        guard let session = activeSession else { return }
        session.monitoredDurationSeconds = accumulator.monitoredSeconds
        session.withinThresholdSeconds = accumulator.withinThresholdSeconds
        session.sustainedDeviationSeconds = accumulator.sustainedDeviationSeconds
        session.reminderCount = accumulator.reminderCount
    }
}
