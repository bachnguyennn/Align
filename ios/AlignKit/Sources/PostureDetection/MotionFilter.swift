import Foundation
import AlignCore

/// Time-constant exponential smoothing of the head-frame gravity unit vector:
/// `alpha = 1 - exp(-dt / tau)`, output renormalized. Being time-based, the response is the same
/// at any sample rate. The first sample after `init` or `reset()` initializes the output.
/// Mirrors `align_reference/motion_filter.py`.
public struct MotionFilter: Sendable {
    public private(set) var value: Vector3?
    public private(set) var lastTimestamp: TimeInterval?

    public init() {}

    public mutating func reset() {
        value = nil
        lastTimestamp = nil
    }

    /// Feeds one unit gravity vector and returns the smoothed unit vector.
    @discardableResult
    public mutating func update(gravity: Vector3, timestamp: TimeInterval, timeConstant: TimeInterval) -> Vector3 {
        guard let current = value, let last = lastTimestamp else {
            value = gravity
            lastTimestamp = timestamp
            return gravity
        }
        var dt = timestamp - last
        if dt < 0 {
            dt = 0
        }
        let alpha: Double
        if timeConstant <= 0 {
            alpha = 1
        } else {
            alpha = 1 - exp(-dt / timeConstant)
        }
        let blended = current + (gravity - current) * alpha
        var result = blended.normalized
        if result.length == 0 {
            result = gravity
        }
        value = result
        lastTimestamp = timestamp
        return result
    }
}
