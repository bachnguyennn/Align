# Sensor and posture contracts

Owner: Lead Architect. Version: v1. The Swift source of truth is `ios/AlignKit/Sources/AlignCore`.
Agents may not change AlignCore directly: propose a change in your report and the Lead
Architect records it in `decisions.md`.

## 1. SensorProvider (AlignCore) — implemented by the Sensor agent

`@MainActor protocol SensorProvider` — see `Sensor.swift`.

- `start()` returns a fresh `AsyncStream<SensorEvent>` and finishes any earlier one. The first
  event is always `.connectionChanged(currentState)`.
- `stop()` emits `.connectionChanged(.idle)` and finishes the stream.
- Every `.sample` must have `gravity` set (head frame, in g).
- Unavailable hardware → `.connectionChanged(.unavailable(.motionNotSupported))`, and the stream
  stays open until `stop()`.
- Denied/restricted authorization → `.connectionChanged(.unavailable(.notAuthorized))`.
- Headphones connect/disconnect → `.connected` / `.waitingForHeadphones`.
- Core Motion error → `.failed(message:)`.

### Sensors module public API (Sensor agent delivers exactly this)

```swift
// iOS only (#if os(iOS)):
@MainActor public final class RealAirPodsSensorProvider: SensorProvider {
    public init()
}

// All platforms, deterministic:
@MainActor public final class MockSensorProvider: SensorProvider {
    public init(scenario: MockScenario = .manual, sampleRateHz: Double = 25, timeScale: Double = 1)
    public var scenario: MockScenario { get set }      // restarts the scenario if streaming
    /// For `.manual`: the head pose to simulate (degrees, same sign convention as TiltEstimate).
    public func setSimulatedTilt(forwardDegrees: Double, lateralDegrees: Double)
}

public enum MockScenario: String, CaseIterable, Sendable {
    case manual                 // pose set by setSimulatedTilt; small realistic noise
    case steadyNeutral
    case gradualForwardSlouch   // neutral 20 s, drifts to ~25° forward, holds 60 s, returns
    case briefGlanceDown        // repeated 3–5 s glances to ~30° forward
    case lateralTilt            // holds ~20° right tilt for 45 s
    case disconnectMidSession   // streams 20 s, disconnects 10 s, reconnects
    case unavailable            // .unavailable(.motionNotSupported)
    case permissionDenied       // .unavailable(.notAuthorized)
}

/// Measures delivered sample rate for diagnostics.
public struct SampleRateMeter: Sendable {
    public init(window: TimeInterval = 5)
    public mutating func record(_ timestamp: TimeInterval)
    public var samplesPerSecond: Double? { get }
    public var largestGap: TimeInterval? { get }
}
```

The mock produces samples whose `gravity`/`attitude` agree with `HeadAxisConvention.airPodsDefault`,
so a mock forward tilt of +20° yields `TiltEstimate.forwardDegrees ≈ +20`.

## 2. PostureMonitor (PostureDetection) — implemented by the Algorithm agent

```swift
public final class PostureMonitor {
    public init(configuration: PostureConfiguration = .default, baseline: NeutralBaseline? = nil)
    public var configuration: PostureConfiguration { get set }   // applies from the next sample
    public private(set) var baseline: NeutralBaseline? { get }
    public var state: PostureState { get }

    /// Starts collecting a new baseline from subsequent samples.
    public func beginCalibration()
    public func cancelCalibration()
    /// Feeds one sample. Not thread-safe; call from one actor.
    public func process(_ sample: MotionSample) -> PostureUpdate
    /// Call on disconnect/pause. Closes any open episode (returned in completedEpisode),
    /// fails an in-progress calibration with .sensorInterrupted, and resets timers.
    public func interrupt(at timestamp: TimeInterval) -> PostureUpdate
    /// Clears reminder cooldown (e.g. new session).
    public func resetCooldown()

    // D-017 guided-nod axis calibration
    /// Axes in use: `baseline?.learnedAxes ?? configuration.axes`.
    public var effectiveAxes: HeadAxisConvention { get }
    /// Starts waiting for one nod. Requires a baseline; without one, the next update reports
    /// `.failed(.needsBaseline)`. Cancels a neutral calibration in progress.
    public func beginAxisCalibration()
    public func cancelAxisCalibration()
    /// Removes learned axes from the baseline (back to `configuration.axes`).
    public func clearLearnedAxes()
}
```

### Axis calibration (D-017)

- While active: `state == .calibrating(progress)` with progress = elapsed / `axisCalibrationDuration`;
  no deviation timers, reminders or episodes (as during neutral calibration). An open episode is
  closed on the first update, as `beginCalibration()` does.
- Head rotation of each smoothed sample relative to the baseline gravity is computed as in the
  tilt estimate (it lies in the baseline plane; heading never contributes).
- Success needs a peak of at least `axisCalibrationMinimumNodDegrees`. The forward axis line is
  the dominant direction of the rotation vectors above a small floor; its sign is chosen so that
  it has a non-negative dot product with the default forward axis projected onto the baseline
  plane (a nod down or up both work). Reject with `.inconsistentMotion` if that angle exceeds
  `axisCalibrationMaxYawDegrees`, or if sideways ÷ forward motion exceeds
  `axisCalibrationMaxOffAxisRatio`. Lateral axis = normalized(baseline gravity × forward).
- It finishes on the first update after the head returns near neutral following a valid peak,
  or at `axisCalibrationDuration` (then `.noNodDetected` if no valid peak). Exactly one update
  carries `axisCalibrationOutcome`.
- On success the baseline gets `learnedAxes` and `version + 1`; tilt from the next sample uses
  them. `interrupt` or a sample gap fails it with `.sensorInterrupted`.
- A successful neutral calibration produces a baseline with `learnedAxes == nil`.
- Neutral calibration: `.tooMuchMovement` unless at least `calibrationSpreadQuantile` of the
  samples are within `calibrationMaxSpreadDegrees` of the mean (1.0 = v1 rule).

Internal components (public for testing): `MotionFilter`, `CalibrationService`, `PostureDetector`,
`ReminderDecisionEngine`.

### Behavior

- No baseline → `.needsCalibration`; `tilt == nil`.
- `beginCalibration()` → `.calibrating(progress)` for `calibrationDuration`, then exactly one
  update with `calibrationOutcome` set. On success the baseline `version` = previous + 1 (or 1).
- With a baseline: `.neutral` → `.deviating` when a smoothed tilt component crosses its threshold
  → `.sustainedTilt` after `sustainedDuration` → back to `.neutral` once below `threshold − hysteresis`.
- `reminder` is non-nil on the first update in a sustained tilt at which at least
  `reminderCooldown` has passed since the last reminder. A tilt that becomes sustained during the
  cooldown therefore reminds when the cooldown ends, if it is still sustained (D-016). Never more
  than one reminder per episode.
- `completedEpisode` is set when a sustained tilt ends or on `interrupt`.
- A gap greater than `maxSampleGap` acts like `interrupt` at the previous sample's timestamp.
- Direction precedence when several thresholds are exceeded: the component with the largest
  ratio of |angle| to its threshold.

## 3. Replay fixtures — owned by the Algorithm agent

`shared/fixtures/motion/*.json`, format documented in `shared/fixtures/README.md`. Fixtures may
use the action `beginAxisCalibration`; references then include `axisCalibrationOutcomes`. Both
`analytics/align-tools` (Java) and `PostureDetectionTests` (Swift) must replay the same files
and agree on expected reminders and episodes.
