import Foundation
import AlignCore

/// The posture pipeline (docs/agents/sensor-contracts.md §2). Mirrors
/// `analytics/experiments/align_reference/monitor.py`, which is the executable specification.
///
/// Per sample:
/// 1. Validate: gravity (or, if missing, gravity derived from the attitude) must be non-zero and
///    timestamps must strictly increase; otherwise the sample is ignored (passive update).
/// 2. Gap check: a gap to the previous received sample longer than `maxSampleGap` acts like
///    `interrupt(at: previousTimestamp)`; this sample is then processed from a fresh state.
/// 3. Decimation by `maxProcessingRateHz` (phase-accumulating schedule, so 25 Hz capped at 10 Hz
///    gives 10 Hz on average). Dropped samples give a passive update.
/// 4. `MotionFilter` → `CalibrationService` (while calibrating) or `TiltEstimator` +
///    `PostureDetector` → `ReminderDecisionEngine` on the update where a tilt becomes sustained.
///
/// Not thread-safe; call from one actor.
public final class PostureMonitor {
    /// Applies from the next sample.
    public var configuration: PostureConfiguration
    public private(set) var baseline: NeutralBaseline?
    /// Timestamp of the last sample that went through the pipeline (not dropped or ignored).
    public private(set) var lastProcessedTimestamp: TimeInterval?

    private var filter = MotionFilter()
    private var calibration = CalibrationService()
    private var detector = PostureDetector()
    private var reminders = ReminderDecisionEngine()
    private var lastReceivedTimestamp: TimeInterval?
    private var nextProcessingDue: TimeInterval?
    private var hasData = false
    private var lastTilt: TiltEstimate?
    private var pendingEpisode: PostureEpisode?

    public init(configuration: PostureConfiguration = .default, baseline: NeutralBaseline? = nil) {
        self.configuration = configuration
        self.baseline = baseline
    }

    // MARK: - Public API

    /// `.calibrating` while calibrating; `.unavailable` before the first sample and after an
    /// interrupt; `.needsCalibration` without a baseline; otherwise the detector state.
    public var state: PostureState {
        if calibration.isActive {
            return .calibrating(progress: calibration.progress(duration: configuration.calibrationDuration))
        }
        if !hasData {
            return .unavailable
        }
        if baseline == nil {
            return .needsCalibration
        }
        return detector.state
    }

    /// Starts collecting a new baseline from subsequent samples. An open sustained episode is
    /// closed at the last processed timestamp and delivered with the next update.
    public func beginCalibration() {
        if detector.phase != .neutral {
            let end = lastProcessedTimestamp ?? 0
            let episode = detector.interrupt(at: end)
            if pendingEpisode == nil {
                pendingEpisode = episode
            }
        }
        detector.reset()
        calibration.begin()
    }

    /// Stops an in-progress calibration without an outcome; the previous baseline is kept.
    public func cancelCalibration() {
        calibration.cancel()
        detector.reset()
    }

    /// Clears reminder cooldown (e.g. new session).
    public func resetCooldown() {
        reminders.reset()
    }

    /// Call on disconnect/pause. Closes any open episode (returned in `completedEpisode`), fails an
    /// in-progress calibration with `.sensorInterrupted`, and resets filter and timers. The
    /// reminder cooldown is kept.
    public func interrupt(at timestamp: TimeInterval) -> PostureUpdate {
        let result = interruptCore(at: timestamp)
        return PostureUpdate(
            timestamp: timestamp,
            tilt: nil,
            state: state,
            reminder: nil,
            completedEpisode: result.episode,
            calibrationOutcome: result.outcome
        )
    }

    /// Feeds one sample. Not thread-safe; call from one actor.
    public func process(_ sample: MotionSample) -> PostureUpdate {
        let t = sample.timestamp
        let raw = sample.gravity ?? TiltEstimator.gravity(fromAttitude: sample.attitude)
        let gravity = raw.normalized
        if gravity.length == 0 {
            return passiveUpdate(t, episode: nil, outcome: nil)
        }
        if let last = lastReceivedTimestamp, t <= last {
            return passiveUpdate(t, episode: nil, outcome: nil)
        }

        var gapEpisode: PostureEpisode?
        var gapOutcome: CalibrationOutcome?
        if let last = lastReceivedTimestamp, t - last > configuration.maxSampleGap {
            let result = interruptCore(at: last)
            gapEpisode = result.episode
            gapOutcome = result.outcome
        }
        lastReceivedTimestamp = t

        if !shouldProcess(t) {
            return passiveUpdate(t, episode: gapEpisode, outcome: gapOutcome)
        }

        let config = configuration
        let smoothed = filter.update(gravity: gravity, timestamp: t, timeConstant: config.smoothingTimeConstant)
        hasData = true
        lastProcessedTimestamp = t

        var episode = takePendingEpisode() ?? gapEpisode
        var outcome = gapOutcome
        var reminder: ReminderDecision?
        var tilt: TiltEstimate?

        if calibration.isActive {
            let step = calibration.add(gravity: smoothed, timestamp: t, configuration: config)
            switch step {
            case .inProgress:
                break
            case let .succeeded(meanGravity, sampleCount):
                let previousVersion = baseline?.version ?? 0
                let newBaseline = NeutralBaseline(
                    gravity: meanGravity,
                    capturedAt: PostureMonitor.date(forTimestamp: t),
                    sampleCount: sampleCount,
                    version: previousVersion + 1
                )
                baseline = newBaseline
                outcome = .succeeded(newBaseline)
                detector.reset()
            case let .failed(failure, _):
                outcome = .failed(failure)
                detector.reset()
            }
            if let b = baseline {
                tilt = estimate(t, smoothed, b)
            }
        } else if let b = baseline {
            let current = estimate(t, smoothed, b)
            tilt = current
            let out = detector.update(current, configuration: config)
            if episode == nil, let completed = out.completedEpisode {
                episode = completed
            }
            // Evaluated on every sustained update until this episode has reminded, so a tilt that
            // became sustained during the cooldown still reminds once the cooldown ends (D-016).
            if detector.phase == .sustained, !detector.reminderTriggered,
               let direction = detector.direction, let start = detector.since {
                let decision = reminders.evaluate(
                    timestamp: t,
                    direction: direction,
                    deviationDegrees: PostureDetector.component(current, direction),
                    sustainedSeconds: t - start,
                    cooldown: config.reminderCooldown
                )
                if let decision = decision {
                    detector.markReminderTriggered()
                    reminder = decision
                }
            }
        }

        lastTilt = tilt
        return PostureUpdate(
            timestamp: t,
            tilt: tilt,
            state: state,
            reminder: reminder,
            completedEpisode: episode,
            calibrationOutcome: outcome
        )
    }

    // MARK: - Internals

    /// Converts a monotonic sample timestamp to a wall-clock date (docs/agents/architecture.md, Time).
    static func date(forTimestamp timestamp: TimeInterval) -> Date {
        Date(timeIntervalSinceNow: timestamp - ProcessInfo.processInfo.systemUptime)
    }

    private func estimate(_ t: TimeInterval, _ smoothed: Vector3, _ b: NeutralBaseline) -> TiltEstimate {
        TiltEstimator.estimate(timestamp: t, gravity: smoothed, baseline: b.gravity, axes: configuration.axes)
    }

    private func takePendingEpisode() -> PostureEpisode? {
        let episode = pendingEpisode
        pendingEpisode = nil
        return episode
    }

    private func interruptCore(at timestamp: TimeInterval) -> (episode: PostureEpisode?, outcome: CalibrationOutcome?) {
        let pending = takePendingEpisode()
        let detectorEpisode = detector.interrupt(at: timestamp)
        let episode = pending ?? detectorEpisode
        var outcome: CalibrationOutcome?
        if calibration.isActive {
            calibration.cancel()
            outcome = .failed(.sensorInterrupted)
        }
        filter.reset()
        hasData = false
        lastReceivedTimestamp = nil
        lastProcessedTimestamp = nil
        nextProcessingDue = nil
        lastTilt = nil
        return (episode: episode, outcome: outcome)
    }

    private func shouldProcess(_ t: TimeInterval) -> Bool {
        guard let rate = configuration.maxProcessingRateHz, rate > 0 else {
            nextProcessingDue = nil
            return true
        }
        let period = 1.0 / rate
        guard let due = nextProcessingDue else {
            nextProcessingDue = t + period
            return true
        }
        if t + PostureDetectionConstants.decimationEpsilon < due {
            return false
        }
        var next = due + period
        if next <= t {
            next = t + period
        }
        nextProcessingDue = next
        return true
    }

    private func passiveUpdate(_ t: TimeInterval, episode: PostureEpisode?, outcome: CalibrationOutcome?) -> PostureUpdate {
        let pending = takePendingEpisode()
        return PostureUpdate(
            timestamp: t,
            tilt: lastTilt,
            state: state,
            reminder: nil,
            completedEpisode: episode ?? pending,
            calibrationOutcome: outcome
        )
    }
}
