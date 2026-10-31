import Foundation
import AlignCore

/// The posture pipeline (docs/agents/sensor-contracts.md §2). Mirrors
/// `PostureMonitor` in `analytics/align-tools` (Java), which is the executable specification.
///
/// Per sample:
/// 1. Validate: gravity (or, if missing, gravity derived from the attitude) must be non-zero and
///    timestamps must strictly increase; otherwise the sample is ignored (passive update).
/// 2. Gap check: a gap to the previous received sample longer than `maxSampleGap` acts like
///    `interrupt(at: previousTimestamp)`; this sample is then processed from a fresh state.
/// 3. Decimation by `maxProcessingRateHz` (phase-accumulating schedule, so 25 Hz capped at 10 Hz
///    gives 10 Hz on average). Dropped samples give a passive update.
/// 4. `MotionFilter` → `CalibrationService` (neutral calibration), `AxisCalibrationService`
///    (guided nod, D-017), or `TiltEstimator` with `effectiveAxes` + `PostureDetector` →
///    `ReminderDecisionEngine` on every sustained update until the episode has reminded.
///
/// Axis calibration: while active the state is `.calibrating(elapsed / axisCalibrationDuration)`
/// and the detector, reminders and episodes are paused, as during neutral calibration. Exactly one
/// update carries `axisCalibrationOutcome`. `beginAxisCalibration()` and `beginCalibration()`
/// cancel each other's attempt without an outcome; without a baseline, `beginAxisCalibration()`
/// reports `.needsBaseline` on the next update (of any kind).
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
    private var axisCalibration = AxisCalibrationService()
    private var detector = PostureDetector()
    private var reminders = ReminderDecisionEngine()
    private var lastReceivedTimestamp: TimeInterval?
    private var nextProcessingDue: TimeInterval?
    private var hasData = false
    private var lastTilt: TiltEstimate?
    private var pendingEpisode: PostureEpisode?
    private var pendingAxisOutcome: AxisCalibrationOutcome?

    public init(configuration: PostureConfiguration = .default, baseline: NeutralBaseline? = nil) {
        self.configuration = configuration
        self.baseline = baseline
    }

    // MARK: - Public API

    /// Axes in use: `baseline?.learnedAxes ?? configuration.axes`.
    public var effectiveAxes: HeadAxisConvention {
        baseline?.learnedAxes ?? configuration.axes
    }

    /// `.calibrating` during a neutral or axis calibration; `.unavailable` before the first sample
    /// and after an interrupt; `.needsCalibration` without a baseline; otherwise the detector state.
    public var state: PostureState {
        if calibration.isActive {
            return .calibrating(progress: calibration.progress(duration: configuration.calibrationDuration))
        }
        if axisCalibration.isActive {
            return .calibrating(progress: axisCalibration.progress(duration: configuration.axisCalibrationDuration))
        }
        if !hasData {
            return .unavailable
        }
        if baseline == nil {
            return .needsCalibration
        }
        return detector.state
    }

    /// Starts collecting a new baseline from subsequent samples. Cancels an axis calibration in
    /// progress (no outcome). An open sustained episode is closed at the last processed timestamp
    /// and delivered with the next update.
    public func beginCalibration() {
        closeOpenEpisode()
        axisCalibration.cancel()
        calibration.begin()
    }

    /// Stops an in-progress calibration without an outcome; the previous baseline is kept.
    public func cancelCalibration() {
        calibration.cancel()
        detector.reset()
    }

    /// Starts waiting for one nod (D-017). Cancels a neutral calibration in progress (no outcome).
    /// Without a baseline, the next update reports `.failed(.needsBaseline)`. An open sustained
    /// episode is closed at the last processed timestamp and delivered with the next update.
    public func beginAxisCalibration() {
        calibration.cancel()
        closeOpenEpisode()
        if baseline == nil {
            axisCalibration.cancel()
            pendingAxisOutcome = .failed(.needsBaseline)
            return
        }
        axisCalibration.begin()
    }

    /// Stops an axis calibration in progress without an outcome; the baseline is unchanged.
    public func cancelAxisCalibration() {
        axisCalibration.cancel()
        detector.reset()
    }

    /// Removes learned axes from the baseline (back to `configuration.axes`); the version is kept.
    public func clearLearnedAxes() {
        if var b = baseline, b.learnedAxes != nil {
            b.learnedAxes = nil
            baseline = b
        }
    }

    /// Clears reminder cooldown (e.g. new session).
    public func resetCooldown() {
        reminders.reset()
    }

    /// Call on disconnect/pause. Closes any open episode (returned in `completedEpisode`), fails an
    /// in-progress neutral or axis calibration with `.sensorInterrupted`, and resets filter and
    /// timers. The reminder cooldown is kept.
    public func interrupt(at timestamp: TimeInterval) -> PostureUpdate {
        let result = interruptCore(at: timestamp)
        let pendingAxis = takePendingAxisOutcome()
        return PostureUpdate(
            timestamp: timestamp,
            tilt: nil,
            state: state,
            reminder: nil,
            completedEpisode: result.episode,
            calibrationOutcome: result.outcome,
            axisCalibrationOutcome: result.axisOutcome ?? pendingAxis
        )
    }

    /// Feeds one sample. Not thread-safe; call from one actor.
    public func process(_ sample: MotionSample) -> PostureUpdate {
        let t = sample.timestamp
        let raw = sample.gravity ?? TiltEstimator.gravity(fromAttitude: sample.attitude)
        let gravity = raw.normalized
        if gravity.length == 0 {
            return passiveUpdate(t, episode: nil, outcome: nil, axisOutcome: nil)
        }
        if let last = lastReceivedTimestamp, t <= last {
            return passiveUpdate(t, episode: nil, outcome: nil, axisOutcome: nil)
        }

        var gapEpisode: PostureEpisode?
        var gapOutcome: CalibrationOutcome?
        var gapAxisOutcome: AxisCalibrationOutcome?
        if let last = lastReceivedTimestamp, t - last > configuration.maxSampleGap {
            let result = interruptCore(at: last)
            gapEpisode = result.episode
            gapOutcome = result.outcome
            gapAxisOutcome = result.axisOutcome
        }
        lastReceivedTimestamp = t

        if !shouldProcess(t) {
            return passiveUpdate(t, episode: gapEpisode, outcome: gapOutcome, axisOutcome: gapAxisOutcome)
        }

        let config = configuration
        let smoothed = filter.update(gravity: gravity, timestamp: t, timeConstant: config.smoothingTimeConstant)
        hasData = true
        lastProcessedTimestamp = t

        var episode = takePendingEpisode() ?? gapEpisode
        var outcome = gapOutcome
        var axisOutcome = takePendingAxisOutcome() ?? gapAxisOutcome
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
        } else if axisCalibration.isActive, let current = baseline {
            let step = axisCalibration.add(
                gravity: smoothed,
                timestamp: t,
                baselineGravity: current.gravity,
                configuration: config
            )
            switch step {
            case .inProgress:
                break
            case let .succeeded(axes):
                var updated = current
                updated.learnedAxes = axes
                updated.version = current.version + 1
                baseline = updated
                axisOutcome = .succeeded(axes)
                detector.reset()
            case let .failed(failure):
                axisOutcome = .failed(failure)
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
            calibrationOutcome: outcome,
            axisCalibrationOutcome: axisOutcome
        )
    }

    // MARK: - Internals

    /// Converts a monotonic sample timestamp to a wall-clock date (docs/agents/architecture.md, Time).
    static func date(forTimestamp timestamp: TimeInterval) -> Date {
        Date(timeIntervalSinceNow: timestamp - ProcessInfo.processInfo.systemUptime)
    }

    /// Tilt relative to `b`, measured with `b.learnedAxes ?? configuration.axes` (= `effectiveAxes`
    /// for the monitor's own baseline).
    private func estimate(_ t: TimeInterval, _ smoothed: Vector3, _ b: NeutralBaseline) -> TiltEstimate {
        TiltEstimator.estimate(
            timestamp: t,
            gravity: smoothed,
            baseline: b.gravity,
            axes: b.learnedAxes ?? configuration.axes
        )
    }

    /// Closes an open sustained episode at the last processed timestamp (delivered with the next update).
    private func closeOpenEpisode() {
        if detector.phase != .neutral {
            let end = lastProcessedTimestamp ?? 0
            let episode = detector.interrupt(at: end)
            if pendingEpisode == nil {
                pendingEpisode = episode
            }
        }
        detector.reset()
    }

    private func takePendingEpisode() -> PostureEpisode? {
        let episode = pendingEpisode
        pendingEpisode = nil
        return episode
    }

    private func takePendingAxisOutcome() -> AxisCalibrationOutcome? {
        let outcome = pendingAxisOutcome
        pendingAxisOutcome = nil
        return outcome
    }

    private func interruptCore(at timestamp: TimeInterval) -> (
        episode: PostureEpisode?,
        outcome: CalibrationOutcome?,
        axisOutcome: AxisCalibrationOutcome?
    ) {
        let pending = takePendingEpisode()
        let detectorEpisode = detector.interrupt(at: timestamp)
        let episode = pending ?? detectorEpisode
        var outcome: CalibrationOutcome?
        if calibration.isActive {
            calibration.cancel()
            outcome = .failed(.sensorInterrupted)
        }
        var axisOutcome: AxisCalibrationOutcome?
        if axisCalibration.isActive {
            axisCalibration.cancel()
            axisOutcome = .failed(.sensorInterrupted)
        }
        filter.reset()
        hasData = false
        lastReceivedTimestamp = nil
        lastProcessedTimestamp = nil
        nextProcessingDue = nil
        lastTilt = nil
        return (episode: episode, outcome: outcome, axisOutcome: axisOutcome)
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

    private func passiveUpdate(
        _ t: TimeInterval,
        episode: PostureEpisode?,
        outcome: CalibrationOutcome?,
        axisOutcome: AxisCalibrationOutcome?
    ) -> PostureUpdate {
        let pending = takePendingEpisode()
        let pendingAxis = takePendingAxisOutcome()
        return PostureUpdate(
            timestamp: t,
            tilt: lastTilt,
            state: state,
            reminder: nil,
            completedEpisode: episode ?? pending,
            calibrationOutcome: outcome,
            axisCalibrationOutcome: axisOutcome ?? pendingAxis
        )
    }
}
