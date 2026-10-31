import Foundation
import AlignCore

/// Collects `calibrationDuration` seconds of smoothed gravity, measured from the first sample it
/// receives after `begin()`. Baseline = normalized mean. Fails with `.insufficientSamples` if fewer
/// than `minimumCalibrationSamples` were collected, otherwise with `.tooMuchMovement` if any sample
/// is more than `calibrationMaxSpreadDegrees` from the mean.
/// Mirrors `align_reference/calibration.py`.
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

    public init() {}

    public var sampleCount: Int { samples.count }

    public mutating func begin() {
        isActive = true
        startTimestamp = nil
        lastTimestamp = nil
        samples = []
    }

    public mutating func cancel() {
        isActive = false
        startTimestamp = nil
        lastTimestamp = nil
        samples = []
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
        let elapsed = timestamp - (startTimestamp ?? timestamp)
        let duration = configuration.calibrationDuration
        if elapsed + PostureDetectionConstants.timeEpsilon < duration {
            return .inProgress(progress: progress(duration: duration))
        }

        let collected = samples
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
        for g in collected {
            if TiltEstimator.angleDegrees(between: g, and: mean) > limit {
                return .failed(.tooMuchMovement, sampleCount: count)
            }
        }
        return .succeeded(meanGravity: mean, sampleCount: count)
    }
}
