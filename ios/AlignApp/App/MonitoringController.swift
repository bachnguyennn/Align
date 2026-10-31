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

/// The guided-nod step that follows a neutral calibration (D-017 (a)).
enum AxisCalibrationPhase: Equatable {
    case idle
    /// Nod requested, waiting for samples.
    case waitingForSensor
    case inProgress(progress: Double)
    /// The baseline now carries these learned axes (stored).
    case succeeded(HeadAxisConvention)
    case failed(AxisCalibrationFailure)
    /// The user skipped the nod; the default axes stay in use.
    case skipped
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
    private(set) var axisCalibrationPhase: AxisCalibrationPhase = .idle
    /// True after the sample watchdog interrupted a silent stream, until the next sample.
    private(set) var isSampleStalled = false
    /// How many times the watchdog fired since launch (shown in Diagnostics).
    private(set) var sampleStallCount = 0

    private var demoScenarioStorage: MockScenario = .manual
    private var demoForwardStorage: Double = 0
    private var demoLateralStorage: Double = 0

    // MARK: Dependencies and internals

    let settings: SettingsStore
    /// Opt-in diagnostic motion recording (D-017 (d)); fed from the sample stream.
    let recorder: MotionRecorder
    private let notifier: ReminderNotifier
    private let store: SessionStore
    private let makeProvider: @MainActor (Bool) -> any SensorProvider
    private let sampleWatchdog: SampleWatchdog

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

    /// - Parameters:
    ///   - makeProvider: builds the sensor provider; the argument is the demo-mode flag.
    ///   - sampleWatchdog: detects a connected stream that went silent; a real-time one when nil.
    ///   - recorder: the diagnostic motion recorder; one writing to the temporary folder when nil.
    init(
        settings: SettingsStore,
        notifier: ReminderNotifier,
        store: SessionStore,
        makeProvider: @escaping @MainActor (Bool) -> any SensorProvider,
        sampleWatchdog: SampleWatchdog? = nil,
        recorder: MotionRecorder? = nil
    ) {
        self.settings = settings
        self.notifier = notifier
        self.store = store
        self.makeProvider = makeProvider
        self.sampleWatchdog = sampleWatchdog ?? SampleWatchdog()
        self.recorder = recorder ?? MotionRecorder()
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
        self.sampleWatchdog.onStall = { [weak self] in
            self?.handleSampleStall()
        }
    }

    // MARK: Derived state

    /// The stored baseline. Every change of the monitor's baseline is written here at once, so
    /// it always equals `PostureMonitor.baseline`.
    var baseline: NeutralBaseline? { settings.baseline }

    /// A neutral calibration (or the guided nod after it) is running.
    var isCalibrating: Bool {
        isNeutralCalibrating || isAxisCalibrating
    }

    var isNeutralCalibrating: Bool {
        switch calibrationPhase {
        case .waitingForSensor, .inProgress:
            return true
        case .idle, .succeeded, .failed:
            return false
        }
    }

    var isAxisCalibrating: Bool {
        switch axisCalibrationPhase {
        case .waitingForSensor, .inProgress:
            return true
        case .idle, .succeeded, .failed, .skipped:
            return false
        }
    }

    /// Axes the monitor measures tilt with: learned from the nod, else the default convention.
    var effectiveAxes: HeadAxisConvention {
        baseline?.learnedAxes ?? settings.configuration.axes
    }

    var hasLearnedAxes: Bool {
        baseline?.learnedAxes != nil
    }

    /// Signed angle of the learned forward axis from the default one, both projected onto the
    /// baseline plane (positive toward the default lateral axis). Nil without learned axes.
    var learnedAxisYawDegrees: Double? {
        guard let baseline, let learned = baseline.learnedAxes else { return nil }
        return AxisCalibrationService.signedYawDegrees(
            forwardAxis: learned.forwardAxis,
            baselineGravity: baseline.gravity,
            reference: settings.configuration.axes
        )
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

    /// Starts a neutral calibration. A new baseline never has learned axes (each earbud fit is
    /// new, D-017), so success also clears them in storage.
    /// - Parameter client: the screen that needs the sensor for it.
    func startCalibration(client: SensorClient = .calibration) {
        if sessionState == .running {
            pauseSession()
        }
        acquireSensor(client)
        // Also cancels a nod in progress (without an outcome).
        perform(.beginCalibration)
        axisCalibrationPhase = .idle
        calibrationPhase = connectionState == .connected ? .inProgress(progress: 0) : .waitingForSensor
    }

    /// Cancels a neutral calibration or a nod in progress. The stored baseline is unchanged.
    func cancelCalibration() {
        guard isCalibrating else { return }
        if isNeutralCalibrating {
            perform(.cancelCalibration)
            calibrationPhase = .idle
        }
        if isAxisCalibrating {
            perform(.cancelAxisCalibration)
            axisCalibrationPhase = .idle
        }
        postureState = monitor.state
    }

    /// Clears finished calibration and nod results so the screen shows its instructions again.
    func acknowledgeCalibrationResult() {
        if !isNeutralCalibrating {
            calibrationPhase = .idle
        }
        if !isAxisCalibrating {
            axisCalibrationPhase = .idle
        }
    }

    /// Starts the guided nod (D-017 (a)). Needs a baseline; without one the phase becomes
    /// `.failed(.needsBaseline)` at once.
    func startAxisCalibration(client: SensorClient = .calibration) {
        guard monitor.baseline != nil else {
            axisCalibrationPhase = .failed(.needsBaseline)
            return
        }
        if sessionState == .running {
            pauseSession()
        }
        if isNeutralCalibrating {
            // beginAxisCalibration cancels it without an outcome.
            calibrationPhase = .idle
        }
        acquireSensor(client)
        perform(.beginAxisCalibration)
        axisCalibrationPhase = connectionState == .connected ? .inProgress(progress: 0) : .waitingForSensor
    }

    func cancelAxisCalibration() {
        guard isAxisCalibrating else { return }
        perform(.cancelAxisCalibration)
        axisCalibrationPhase = .idle
        postureState = monitor.state
    }

    /// Skips the nod after a neutral calibration: the baseline keeps `learnedAxes == nil`, so
    /// the default axes stay in use.
    func skipAxisCalibration() {
        if isAxisCalibrating {
            perform(.cancelAxisCalibration)
            postureState = monitor.state
        }
        axisCalibrationPhase = .skipped
    }

    /// Settings → "Use default axes": drops the learned axes from the baseline and stores it.
    func useDefaultAxes() {
        guard monitor.baseline?.learnedAxes != nil else { return }
        if isAxisCalibrating {
            perform(.cancelAxisCalibration)
            axisCalibrationPhase = .idle
        }
        perform(.clearLearnedAxes)
        settings.baseline = monitor.baseline
    }

    /// Deletes the stored baseline. Any session is stopped first.
    func resetCalibration() {
        if sessionState != .idle {
            stopSession()
        }
        if isNeutralCalibrating {
            monitor.cancelCalibration()
        }
        if isAxisCalibrating {
            monitor.cancelAxisCalibration()
        }
        settings.baseline = nil
        monitor = PostureMonitor(configuration: settings.configuration, baseline: nil)
        latestTilt = nil
        postureState = monitor.state
        calibrationPhase = .idle
        axisCalibrationPhase = .idle
    }

    // MARK: Diagnostic motion recording (D-017 (d))

    /// Recording needs a connected, streaming sensor (the Diagnostics screen holds it).
    var canStartRecording: Bool {
        isStreaming && connectionState == .connected && !recorder.isRecording
    }

    /// Starts recording raw samples, the current baseline and configuration, and calibration
    /// actions, for `length`. Kept in memory, then written to a temporary file to share.
    func startRecording(length: RecordingLength, notes: String) {
        guard canStartRecording else { return }
        let metadata = RecordingMetadata(
            appVersion: AppInfo.versionString,
            device: AppInfo.deviceModelIdentifier,
            headphones: sensorSource == .demo ? "mock sensor (demo mode)" : "unknown",
            notes: notes,
            createdAt: Date()
        )
        recorder.start(length: length, metadata: metadata, configuration: monitor.configuration, baseline: monitor.baseline)
    }

    func stopRecording() {
        recorder.stop(.stoppedByUser)
    }

    /// Cancels a recording and deletes its file (leaving Diagnostics, new recording).
    func discardRecording() {
        recorder.discard()
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
            // A recording never continues in the background (D-017 (d)).
            recorder.stop(.appBackgrounded)
            // Don't report a background transition as a sensor failure.
            if isNeutralCalibrating {
                monitor.cancelCalibration()
                calibrationPhase = .idle
            }
            if isAxisCalibrating {
                monitor.cancelAxisCalibration()
                axisCalibrationPhase = .idle
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
        recorder.stop(.sensorStopped)
        sampleWatchdog.disarm()
        isSampleStalled = false
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

    /// Handles one provider event. Called by the stream task (internal so tests can feed events).
    func handle(_ event: SensorEvent) {
        switch event {
        case .connectionChanged(let state):
            let wasConnected = connectionState == .connected
            if connectionState != state {
                connectionState = state
            }
            refreshProviderStatus()
            if state != .connected {
                sampleWatchdog.disarm()
                if isSampleStalled {
                    isSampleStalled = false
                }
                // Recordings stop on disconnect (D-017 (d)); what was captured can still be shared.
                recorder.stop(.disconnected)
            }
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
            if isSampleStalled {
                isSampleStalled = false
            }
            if isStreaming && connectionState == .connected {
                sampleWatchdog.sampleArrived(maxSampleGap: monitor.configuration.maxSampleGap)
            }
            recorder.append(sample)
            let update = monitor.process(sample)
            apply(update, fromSample: true)
        }
    }

    /// The watchdog saw no sample for longer than `maxSampleGap` while connected (D-017 (c)):
    /// interrupt like a disconnect, so open episodes close and no stale tilt is shown. The next
    /// sample resumes normally (the monitor starts from a fresh state).
    private func handleSampleStall() {
        guard isStreaming, connectionState == .connected else { return }
        sampleStallCount += 1
        isSampleStalled = true
        interruptMonitor()
        lastSampleTimestamp = nil
        latestTilt = nil
        latestSample = nil
    }

    // MARK: Posture updates

    /// Calls the monitor and notes the action in a running recording (replayable `actions`).
    private func perform(_ action: RecordedActionType) {
        switch action {
        case .beginCalibration:
            monitor.beginCalibration()
        case .cancelCalibration:
            monitor.cancelCalibration()
        case .beginAxisCalibration:
            monitor.beginAxisCalibration()
        case .cancelAxisCalibration:
            monitor.cancelAxisCalibration()
        case .clearLearnedAxes:
            monitor.clearLearnedAxes()
        case .resetCooldown:
            monitor.resetCooldown()
        case .interrupt:
            interruptMonitor()
            return
        }
        recorder.record(action)
    }

    private func interruptMonitor() {
        let timestamp = lastSampleTimestamp ?? ProcessInfo.processInfo.systemUptime
        recorder.record(.interrupt)
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
            perform(.resetCooldown)
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
        } else if case .calibrating(let progress) = update.state, isNeutralCalibrating {
            calibrationPhase = .inProgress(progress: progress)
        }

        if let axisOutcome = update.axisCalibrationOutcome {
            handleAxisCalibrationOutcome(axisOutcome)
        } else if case .calibrating(let progress) = update.state, isAxisCalibrating {
            axisCalibrationPhase = .inProgress(progress: progress)
        }
    }

    private func handleCalibrationOutcome(_ outcome: CalibrationOutcome) {
        switch outcome {
        case .succeeded(let newBaseline):
            // A new neutral baseline has no learned axes: storing it also clears any old ones.
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

    private func handleAxisCalibrationOutcome(_ outcome: AxisCalibrationOutcome) {
        switch outcome {
        case .succeeded(let axes):
            // The monitor's baseline now carries the learned axes (version + 1): store exactly it.
            settings.baseline = monitor.baseline
            axisCalibrationPhase = .succeeded(axes)
            if let session = activeSession, let version = monitor.baseline?.version {
                session.calibrationVersion = version
                store.save()
            }
        case .failed(let reason):
            axisCalibrationPhase = .failed(reason)
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
