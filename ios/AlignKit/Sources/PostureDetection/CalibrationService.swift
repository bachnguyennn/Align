import Foundation
import AlignCore

/// Collects `calibrationDuration` seconds of smoothed gravity, measured from the first sample it
/// receives after `begin()`. Fails with `.insufficientSamples` if fewer than
/// `minimumCalibrationSamples` were collected.
///
/// Spread rule (D-017): let `m` be the normalized mean of all samples and the inliers the samples
/// within `calibrationMaxSpreadDegrees` of `m`. Fails with `.tooMuchMovement` unless the inliers are
/// at least `calibrationSpreadQuantile` of the samples (1.0 = the v1 rule "every sample").
/// Baseline = normalized mean of the inliers, so a brief fidget does not bias it; when every
/// sample is an inlier this is exactly `m`, identical to v1.
///
/// Drift rule (D-020), checked after the spread rule: fails with `.tooMuchMovement` if the
/// normalized mean gravity of the samples in the first `calibrationDriftWindow` seconds
/// (t − start ≤ window) and that of the samples in the last `calibrationDriftWindow` seconds
/// (last − t ≤ window) are more than `calibrationMaxDriftDegrees` apart. It catches a slow slouch,
/// which the spread rule cannot (every sample stays near the mean of the ramp).
/// Mirrors `CalibrationService` in `analytics/align-tools`.
public struct CalibrationService: Sendable {
    public enum Step: Equatable, Sendable {
        case inProgress(progress: Double)
        case succeeded(meanGravity: Vector3, sampleCount: Int)
        case failed(CalibrationFailure, sampleCount: Int)
    }

    public private(set) var isActive = false
    public private(set) var startTimestamp: TimeInterval?
    public private(set) var lastTimestamp: TimeInterval?
    private var samples: [Vector3] = []
    private var timestamps: [TimeInterval] = []

    public init() {}

    public var sampleCount: Int { samples.count }

    public mutating func begin() {
        isActive = true
        startTimestamp = nil
        lastTimestamp = nil
        samples = []
        timestamps = []
    }

    public mutating func cancel() {
        isActive = false
        startTimestamp = nil
        lastTimestamp = nil
        samples = []
        timestamps = []
    }

    /// Angle (degrees) between the normalized mean of the samples with t − first ≤ window and that
    /// of the samples with last − t ≤ window (D-020). `gravities` and `times` are non-empty and
    /// parallel; times are in increasing order.
    public static func driftDegrees(_ gravities: [Vector3], times: [TimeInterval], window: TimeInterval) -> Double {
        guard let first = times.first, let last = times.last else {
            return 0
        }
        var head = Vector3.zero
        var tail = Vector3.zero
        for (i, g) in gravities.enumerated() where i < times.count {
            let t = times[i]
            if t - first <= window + PostureDetectionConstants.timeEpsilon {
                head = head + g
            }
            if last - t <= window + PostureDetectionConstants.timeEpsilon {
                tail = tail + g
            }
        }
        return TiltEstimator.angleDegrees(between: head.normalized, and: tail.normalized)
    }

    /// 0...1 while active; 0 before the first sample.
    public func progress(duration: TimeInterval) -> Double {
        guard isActive, let start = startTimestamp, let last = lastTimestamp else {
            return 0
        }
        if duration <= 0 {
            return 1
        }
        let p = (last - start) / duration
        return min(1, max(0, p))
    }

    public mutating func add(gravity: Vector3, timestamp: TimeInterval, configuration: PostureConfiguration) -> Step {
        if startTimestamp == nil {
            startTimestamp = timestamp
        }
        lastTimestamp = timestamp
        samples.append(gravity)
        timestamps.append(timestamp)
        let elapsed = timestamp - (startTimestamp ?? timestamp)
        let duration = configuration.calibrationDuration
        if elapsed + PostureDetectionConstants.timeEpsilon < duration {
            return .inProgress(progress: progress(duration: duration))
        }

        let collected = samples
        let times = timestamps
        cancel()
        let count = collected.count
        if count < configuration.minimumCalibrationSamples {
            return .failed(.insufficientSamples, sampleCount: count)
        }
        var total = Vector3.zero
        for g in collected {
            total = total + g
        }
        let mean = total.normalized
        if mean.length == 0 {
            return .failed(.tooMuchMovement, sampleCount: count)
        }
        let limit = configuration.calibrationMaxSpreadDegrees
        var inliers = 0
        var inlierTotal = Vector3.zero
        for g in collected {
            if TiltEstimator.angleDegrees(between: g, and: mean) <= limit {
                inliers += 1
                inlierTotal = inlierTotal + g
            }
        }
        if !CalibrationService.hasEnoughInliers(inliers, of: count, quantile: configuration.calibrationSpreadQuantile) {
            return .failed(.tooMuchMovement, sampleCount: count)
        }
        let drift = CalibrationService.driftDegrees(collected, times: times, window: configuration.calibrationDriftWindow)
        if !(drift <= configuration.calibrationMaxDriftDegrees) {
            return .failed(.tooMuchMovement, sampleCount: count)
        }
        let baselineGravity = inliers == count ? mean : inlierTotal.normalized
        if baselineGravity.length == 0 {
            return .failed(.tooMuchMovement, sampleCount: count)
        }
        return .succeeded(meanGravity: baselineGravity, sampleCount: count)
    }

    /// True if `inliers` of `count` samples reach `quantile` (clamped to 0...1).
    public static func hasEnoughInliers(_ inliers: Int, of count: Int, quantile: Double) -> Bool {
        let q = min(1.0, max(0.0, quantile))
        return Double(inliers) + PostureDetectionConstants.calibrationQuantileEpsilon * Double(count) >= q * Double(count)
    }
}
