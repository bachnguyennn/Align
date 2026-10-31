import AlignCore
import Foundation

/// A deterministic, simulated head-motion source for the simulator, previews, demos and tests.
///
/// Samples are produced by `MockMotionGenerator` (pure and seeded) and delivered on the main
/// actor by a `Task` that sleeps `1 / (sampleRateHz × timeScale)` seconds between samples.
///
/// Timestamps advance by `1 / sampleRateHz` per sample in *simulated* time, starting at
/// `ProcessInfo.processInfo.systemUptime` when `start()` is called. With `timeScale` > 1 the
/// scenario plays faster than real time while the pipeline still sees the nominal rate, e.g.
/// `timeScale: 10` plays a 60 s slouch in about 6 s. Timestamps never go backwards, including
/// across scenario changes.
@MainActor
public final class MockSensorProvider: SensorProvider {
    public private(set) var connectionState: SensorConnectionState = .idle

    public var authorization: SensorAuthorization {
        generator.scenario == .permissionDenied ? .denied : .authorized
    }

    public var isMotionAvailable: Bool {
        generator.scenario != .unavailable
    }

    /// Changing the scenario while streaming restarts its timeline on the same stream.
    public var scenario: MockScenario {
        get { generator.scenario }
        set {
            generator.scenario = newValue
            restartTimelineIfStreaming()
        }
    }

    public let sampleRateHz: Double
    public let timeScale: Double

    private var generator: MockMotionGenerator
    private var continuation: AsyncStream<SensorEvent>.Continuation?
    private var tickTask: Task<Void, Never>?
    /// Incremented on every start/stop/restart so stale tick tasks stop.
    private var generation = 0
    /// Identifies the current stream so a late termination of an old stream is ignored.
    private var streamID = 0
    private var nextSampleIndex = 0
    private var timelineStartTimestamp: TimeInterval = 0
    private var lastTimestamp: TimeInterval?

    private static let bufferLimit = 500

    public init(scenario: MockScenario = .manual, sampleRateHz: Double = 25, timeScale: Double = 1) {
        let rate = (sampleRateHz.isFinite && sampleRateHz > 0) ? sampleRateHz : 25
        self.sampleRateHz = rate
        self.timeScale = (timeScale.isFinite && timeScale > 0) ? timeScale : 1
        self.generator = MockMotionGenerator(scenario: scenario, sampleRateHz: rate)
    }

    /// For `.manual`: the head pose to simulate (degrees, same sign convention as
    /// `TiltEstimate`). Takes effect from the next sample. Ignored by other scenarios, but
    /// remembered for when `.manual` is selected.
    public func setSimulatedTilt(forwardDegrees: Double, lateralDegrees: Double) {
        generator.manualPose = MockHeadPose(forwardDegrees: forwardDegrees, lateralDegrees: lateralDegrees)
    }

    public func start() -> AsyncStream<SensorEvent> {
        finishCurrentStream()
        generation += 1
        streamID += 1
        let currentStreamID = streamID

        var created: AsyncStream<SensorEvent>.Continuation?
        let stream = AsyncStream<SensorEvent>(bufferingPolicy: .bufferingNewest(Self.bufferLimit)) { continuation in
            created = continuation
        }
        guard let continuation = created else { return stream }
        continuation.onTermination = { [weak self] _ in
            guard let provider = self else { return }
            Task { @MainActor in
                provider.streamTerminated(streamID: currentStreamID)
            }
        }
        self.continuation = continuation
        beginTimeline()
        return stream
    }

    public func stop() {
        generation += 1
        streamID += 1
        tickTask?.cancel()
        tickTask = nil
        connectionState = .idle
        guard let continuation else { return }
        self.continuation = nil
        continuation.yield(.connectionChanged(.idle))
        continuation.finish()
    }

    // MARK: - Timeline

    private func beginTimeline() {
        tickTask?.cancel()
        tickTask = nil
        nextSampleIndex = 0
        let now = ProcessInfo.processInfo.systemUptime
        if let lastTimestamp {
            timelineStartTimestamp = max(now, lastTimestamp + 1 / sampleRateHz)
        } else {
            timelineStartTimestamp = now
        }

        // The first event of a stream is always the current state.
        let initialState = generator.connectionState(at: 0)
        connectionState = initialState
        continuation?.yield(.connectionChanged(initialState))

        guard generator.producesSamples else { return }
        startTicking(generation: generation)
    }

    private func restartTimelineIfStreaming() {
        guard continuation != nil else { return }
        generation += 1
        let previousState = connectionState
        tickTask?.cancel()
        tickTask = nil
        nextSampleIndex = 0
        let now = ProcessInfo.processInfo.systemUptime
        if let lastTimestamp {
            timelineStartTimestamp = max(now, lastTimestamp + 1 / sampleRateHz)
        } else {
            timelineStartTimestamp = now
        }
        let state = generator.connectionState(at: 0)
        if state != previousState {
            connectionState = state
            continuation?.yield(.connectionChanged(state))
        }
        guard generator.producesSamples else { return }
        startTicking(generation: generation)
    }

    private func startTicking(generation tickGeneration: Int) {
        let interval = 1 / (sampleRateHz * timeScale)
        let nanoseconds = UInt64(max(interval, 0.001) * 1_000_000_000)
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    return
                }
                guard let provider = self, provider.generation == tickGeneration else { return }
                provider.tick()
            }
        }
    }

    private func tick() {
        guard let continuation else { return }
        let index = nextSampleIndex
        nextSampleIndex += 1
        let t = generator.time(ofSample: index)
        let state = generator.connectionState(at: t)
        if state != connectionState {
            connectionState = state
            continuation.yield(.connectionChanged(state))
        }
        guard let sample = generator.sample(index: index, startTimestamp: timelineStartTimestamp) else { return }
        lastTimestamp = sample.timestamp
        continuation.yield(.sample(sample))
    }

    // MARK: - Stream lifecycle

    /// Ends the current stream without emitting `.idle` (used when a new stream replaces it).
    private func finishCurrentStream() {
        tickTask?.cancel()
        tickTask = nil
        guard let continuation else { return }
        self.continuation = nil
        continuation.finish()
    }

    /// The consumer stopped listening (e.g. its task was cancelled): stop producing samples.
    private func streamTerminated(streamID terminatedStreamID: Int) {
        guard terminatedStreamID == streamID, continuation != nil else { return }
        generation += 1
        streamID += 1
        tickTask?.cancel()
        tickTask = nil
        continuation = nil
        connectionState = .idle
    }
}
