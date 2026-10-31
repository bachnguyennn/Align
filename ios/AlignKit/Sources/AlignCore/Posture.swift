import Foundation

/// Head tilt relative to the calibrated neutral baseline. Heading (turning the head
/// left/right) is excluded. This is head *rotation*, not forward head *translation*.
public struct TiltEstimate: Equatable, Codable, Sendable {
    public var timestamp: TimeInterval
    /// Positive = chin toward chest (forward flexion); negative = looking up.
    public var forwardDegrees: Double
    /// Positive = right ear toward right shoulder; negative = toward left shoulder.
    public var lateralDegrees: Double
    /// Total tilt angle away from baseline, >= 0.
    public var totalDegrees: Double

    public init(timestamp: TimeInterval, forwardDegrees: Double, lateralDegrees: Double, totalDegrees: Double) {
        self.timestamp = timestamp
        self.forwardDegrees = forwardDegrees
        self.lateralDegrees = lateralDegrees
        self.totalDegrees = totalDegrees
    }
}

public enum TiltDirection: String, Codable, Sendable, CaseIterable {
    case forward
    case backward
    case left
    case right
}

public enum PostureState: Equatable, Sendable {
    /// No usable sensor data (not streaming, disconnected, or a sample gap).
    case unavailable
    /// Streaming, but no baseline exists yet.
    case needsCalibration
    /// Collecting the neutral baseline. `progress` is 0...1.
    case calibrating(progress: Double)
    /// Within thresholds.
    case neutral
    /// Over a threshold, but not yet for `sustainedDuration` (short movement or glance).
    case deviating(direction: TiltDirection, since: TimeInterval)
    /// Over a threshold for at least `sustainedDuration`.
    case sustainedTilt(direction: TiltDirection, since: TimeInterval)
}

public enum CalibrationFailure: String, Error, Codable, Sendable {
    case tooMuchMovement
    case insufficientSamples
    case sensorInterrupted
}

/// Why a guided-nod axis calibration (D-017) did not produce axes.
public enum AxisCalibrationFailure: String, Error, Codable, Sendable {
    /// `beginAxisCalibration()` was called without a neutral baseline.
    case needsBaseline
    /// The head never tilted `axisCalibrationMinimumNodDegrees` away from neutral in time.
    case noNodDetected
    /// The motion was not a single forward/backward nod (too much sideways component, or its
    /// axis is more than `axisCalibrationMaxYawDegrees` from the default forward axis).
    case inconsistentMotion
    case sensorInterrupted
}

/// The user's neutral head position.
public struct NeutralBaseline: Equatable, Codable, Sendable {
    /// Mean unit gravity direction in the head frame while neutral. Independent of heading,
    /// so a stored baseline stays valid across streaming sessions.
    public var gravity: Vector3
    public var capturedAt: Date
    public var sampleCount: Int
    /// Increments on each successful calibration (neutral or axis); stored on sessions as
    /// `calibrationVersion`.
    public var version: Int
    /// Head axes learned from a guided nod for this earbud fit (D-017). Nil = use
    /// `PostureConfiguration.axes`. A new neutral calibration clears it.
    public var learnedAxes: HeadAxisConvention?

    public init(gravity: Vector3, capturedAt: Date, sampleCount: Int, version: Int, learnedAxes: HeadAxisConvention? = nil) {
        self.gravity = gravity
        self.capturedAt = capturedAt
        self.sampleCount = sampleCount
        self.version = version
        self.learnedAxes = learnedAxes
    }
}

public enum CalibrationOutcome: Equatable, Sendable {
    case succeeded(NeutralBaseline)
    case failed(CalibrationFailure)
}

public enum AxisCalibrationOutcome: Equatable, Sendable {
    /// The learned axes; the monitor's baseline now carries them.
    case succeeded(HeadAxisConvention)
    case failed(AxisCalibrationFailure)
}

/// Emitted on the update where a reminder should be delivered now.
public struct ReminderDecision: Equatable, Sendable {
    public var timestamp: TimeInterval
    public var direction: TiltDirection
    public var deviationDegrees: Double
    public var sustainedSeconds: Double

    public init(timestamp: TimeInterval, direction: TiltDirection, deviationDegrees: Double, sustainedSeconds: Double) {
        self.timestamp = timestamp
        self.direction = direction
        self.deviationDegrees = deviationDegrees
        self.sustainedSeconds = sustainedSeconds
    }
}

/// A finished sustained-tilt episode, emitted when the tilt ends or the sensor is interrupted.
/// Only sustained tilts become episodes; short deviations are not recorded.
public struct PostureEpisode: Equatable, Sendable {
    public var direction: TiltDirection
    /// When the deviation began (not when it became sustained).
    public var startTimestamp: TimeInterval
    public var endTimestamp: TimeInterval
    public var peakDeviationDegrees: Double
    public var reminderTriggered: Bool

    public init(direction: TiltDirection, startTimestamp: TimeInterval, endTimestamp: TimeInterval, peakDeviationDegrees: Double, reminderTriggered: Bool) {
        self.direction = direction
        self.startTimestamp = startTimestamp
        self.endTimestamp = endTimestamp
        self.peakDeviationDegrees = peakDeviationDegrees
        self.reminderTriggered = reminderTriggered
    }
}

public struct PostureUpdate: Equatable, Sendable {
    public var timestamp: TimeInterval
    /// Nil until a baseline exists.
    public var tilt: TiltEstimate?
    public var state: PostureState
    public var reminder: ReminderDecision?
    public var completedEpisode: PostureEpisode?
    /// Set only on the update where a calibration attempt finished.
    public var calibrationOutcome: CalibrationOutcome?
    /// Set only on the update where an axis calibration attempt finished (D-017).
    public var axisCalibrationOutcome: AxisCalibrationOutcome?

    public init(
        timestamp: TimeInterval,
        tilt: TiltEstimate? = nil,
        state: PostureState,
        reminder: ReminderDecision? = nil,
        completedEpisode: PostureEpisode? = nil,
        calibrationOutcome: CalibrationOutcome? = nil,
        axisCalibrationOutcome: AxisCalibrationOutcome? = nil
    ) {
        self.timestamp = timestamp
        self.tilt = tilt
        self.state = state
        self.reminder = reminder
        self.completedEpisode = completedEpisode
        self.calibrationOutcome = calibrationOutcome
        self.axisCalibrationOutcome = axisCalibrationOutcome
    }
}

/// Maps head-frame axes to posture directions. Each axis is a unit vector in the head frame;
/// a positive (right-hand rule) rotation of the head about it means the named direction.
/// For a right-handed head frame, `forwardAxis × lateralAxis` points down.
/// Defaults assume +X toward the right ear, +Y toward the nose, +Z up (D-011);
/// they are UNVERIFIED until checked on AirPods Pro hardware (task S-05).
public struct HeadAxisConvention: Equatable, Codable, Sendable {
    /// Positive rotation = chin toward chest.
    public var forwardAxis: Vector3
    /// Positive rotation = right ear toward right shoulder.
    public var lateralAxis: Vector3

    public init(forwardAxis: Vector3, lateralAxis: Vector3) {
        self.forwardAxis = forwardAxis
        self.lateralAxis = lateralAxis
    }

    public static let airPodsDefault = HeadAxisConvention(
        forwardAxis: Vector3(x: -1, y: 0, z: 0),
        lateralAxis: Vector3(x: 0, y: 1, z: 0)
    )
}

/// Tunable detection parameters. Defaults are experimental, not medically validated.
public struct PostureConfiguration: Equatable, Codable, Sendable {
    public var calibrationDuration: TimeInterval = 10
    /// Calibration fails with `.tooMuchMovement` unless at least `calibrationSpreadQuantile` of
    /// the samples lie within this tilt of the calibration mean.
    public var calibrationMaxSpreadDegrees: Double = 5
    /// Fraction of calibration samples that must lie within `calibrationMaxSpreadDegrees`.
    /// 1.0 = every sample (v1 behavior); lower values tolerate a brief fidget (D-017).
    public var calibrationSpreadQuantile: Double = 0.9
    /// Calibration fails with `.tooMuchMovement` if the mean head direction of the first and the
    /// last `calibrationDriftWindow` seconds differ by more than this (a slow slouch, D-020).
    public var calibrationMaxDriftDegrees: Double = 3
    public var calibrationDriftWindow: TimeInterval = 2
    public var minimumCalibrationSamples: Int = 100
    public var forwardThresholdDegrees: Double = 15
    public var backwardThresholdDegrees: Double = 20
    public var lateralThresholdDegrees: Double = 15
    /// A deviation ends only once tilt falls this far below the threshold.
    public var hysteresisDegrees: Double = 3
    public var sustainedDuration: TimeInterval = 30
    public var reminderCooldown: TimeInterval = 300
    /// Time constant of the smoothing filter.
    public var smoothingTimeConstant: TimeInterval = 0.5
    /// Samples arriving faster than this are dropped (decimation). Nil = use every sample.
    public var maxProcessingRateHz: Double? = nil
    /// A gap between samples longer than this resets filters and deviation timers.
    public var maxSampleGap: TimeInterval = 1.0
    public var axes: HeadAxisConvention = .airPodsDefault
    /// Guided-nod axis calibration (D-017): longest time to wait for the nod.
    public var axisCalibrationDuration: TimeInterval = 8
    /// The nod must reach at least this tilt from neutral.
    public var axisCalibrationMinimumNodDegrees: Double = 12
    /// Largest accepted angle between the learned and the default forward axis (earbud yaw in
    /// the ear). Larger means the user tilted sideways rather than nodding.
    public var axisCalibrationMaxYawDegrees: Double = 45
    /// Largest accepted ratio of sideways to forward/backward motion during the nod.
    public var axisCalibrationMaxOffAxisRatio: Double = 0.35

    public init() {}

    public static let `default` = PostureConfiguration()

    private enum CodingKeys: String, CodingKey {
        case calibrationDuration
        case calibrationMaxSpreadDegrees
        case calibrationSpreadQuantile
        case calibrationMaxDriftDegrees
        case calibrationDriftWindow
        case minimumCalibrationSamples
        case forwardThresholdDegrees
        case backwardThresholdDegrees
        case lateralThresholdDegrees
        case hysteresisDegrees
        case sustainedDuration
        case reminderCooldown
        case smoothingTimeConstant
        case maxProcessingRateHz
        case maxSampleGap
        case axes
        case axisCalibrationDuration
        case axisCalibrationMinimumNodDegrees
        case axisCalibrationMaxYawDegrees
        case axisCalibrationMaxOffAxisRatio
    }

    /// Missing keys take their defaults, so a configuration stored by an older app version (which
    /// lacks newer fields) still decodes instead of silently resetting the user's settings.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PostureConfiguration()
        calibrationDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .calibrationDuration) ?? d.calibrationDuration
        calibrationMaxSpreadDegrees = try c.decodeIfPresent(Double.self, forKey: .calibrationMaxSpreadDegrees) ?? d.calibrationMaxSpreadDegrees
        calibrationSpreadQuantile = try c.decodeIfPresent(Double.self, forKey: .calibrationSpreadQuantile) ?? d.calibrationSpreadQuantile
        calibrationMaxDriftDegrees = try c.decodeIfPresent(Double.self, forKey: .calibrationMaxDriftDegrees) ?? d.calibrationMaxDriftDegrees
        calibrationDriftWindow = try c.decodeIfPresent(TimeInterval.self, forKey: .calibrationDriftWindow) ?? d.calibrationDriftWindow
        minimumCalibrationSamples = try c.decodeIfPresent(Int.self, forKey: .minimumCalibrationSamples) ?? d.minimumCalibrationSamples
        forwardThresholdDegrees = try c.decodeIfPresent(Double.self, forKey: .forwardThresholdDegrees) ?? d.forwardThresholdDegrees
        backwardThresholdDegrees = try c.decodeIfPresent(Double.self, forKey: .backwardThresholdDegrees) ?? d.backwardThresholdDegrees
        lateralThresholdDegrees = try c.decodeIfPresent(Double.self, forKey: .lateralThresholdDegrees) ?? d.lateralThresholdDegrees
        hysteresisDegrees = try c.decodeIfPresent(Double.self, forKey: .hysteresisDegrees) ?? d.hysteresisDegrees
        sustainedDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .sustainedDuration) ?? d.sustainedDuration
        reminderCooldown = try c.decodeIfPresent(TimeInterval.self, forKey: .reminderCooldown) ?? d.reminderCooldown
        smoothingTimeConstant = try c.decodeIfPresent(TimeInterval.self, forKey: .smoothingTimeConstant) ?? d.smoothingTimeConstant
        maxProcessingRateHz = try c.decodeIfPresent(Double.self, forKey: .maxProcessingRateHz)
        maxSampleGap = try c.decodeIfPresent(TimeInterval.self, forKey: .maxSampleGap) ?? d.maxSampleGap
        axes = try c.decodeIfPresent(HeadAxisConvention.self, forKey: .axes) ?? d.axes
        axisCalibrationDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .axisCalibrationDuration) ?? d.axisCalibrationDuration
        axisCalibrationMinimumNodDegrees = try c.decodeIfPresent(Double.self, forKey: .axisCalibrationMinimumNodDegrees) ?? d.axisCalibrationMinimumNodDegrees
        axisCalibrationMaxYawDegrees = try c.decodeIfPresent(Double.self, forKey: .axisCalibrationMaxYawDegrees) ?? d.axisCalibrationMaxYawDegrees
        axisCalibrationMaxOffAxisRatio = try c.decodeIfPresent(Double.self, forKey: .axisCalibrationMaxOffAxisRatio) ?? d.axisCalibrationMaxOffAxisRatio
    }
}
