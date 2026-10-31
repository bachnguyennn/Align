import Foundation
import AlignCore
@testable import PostureDetection

/// Noise-free head poses, same model as `align_reference/pose.py`:
/// attitude = Yaw(heading about world Z) * Tilt(rotation vector forward*forwardAxis +
/// lateral*lateralAxis) * Mount(pitch about forwardAxis, roll about lateralAxis).
/// Axes always come from a `HeadAxisConvention` (default: AlignCore's `airPodsDefault`).
enum Pose {
    static let rad = Double.pi / 180

    static func attitude(
        forward: Double,
        lateral: Double,
        heading: Double = 0,
        mountPitch: Double = 0,
        mountRoll: Double = 0,
        axes: HeadAxisConvention = .airPodsDefault
    ) -> Quaternion {
        let rv = axes.forwardAxis * (forward * rad) + axes.lateralAxis * (lateral * rad)
        let tilt = rv.length == 0 ? Quaternion.identity : Quaternion(axis: rv, angleRadians: rv.length)
        let yaw = Quaternion(axis: Vector3(x: 0, y: 0, z: 1), angleRadians: heading * rad)
        let pitch = Quaternion(axis: axes.forwardAxis, angleRadians: mountPitch * rad)
        let roll = Quaternion(axis: axes.lateralAxis, angleRadians: mountRoll * rad)
        let mount = pitch * roll
        return ((yaw * tilt) * mount).normalized
    }

    static func gravity(_ q: Quaternion) -> Vector3 {
        q.normalized.conjugate.rotate(Vector3(x: 0, y: 0, z: -1))
    }

    static func gravity(forward: Double, lateral: Double = 0) -> Vector3 {
        gravity(attitude(forward: forward, lateral: lateral))
    }

    static func sample(
        _ t: TimeInterval,
        forward: Double = 0,
        lateral: Double = 0,
        heading: Double = 0,
        includeGravity: Bool = true
    ) -> MotionSample {
        let q = attitude(forward: forward, lateral: lateral, heading: heading)
        return MotionSample(timestamp: t, attitude: q, gravity: includeGravity ? gravity(q) : nil)
    }
}

func tilt(_ t: TimeInterval, forward: Double = 0, lateral: Double = 0) -> TiltEstimate {
    TiltEstimate(
        timestamp: t,
        forwardDegrees: forward,
        lateralDegrees: lateral,
        totalDegrees: (forward * forward + lateral * lateral).squareRoot()
    )
}

/// Feeds samples for start <= t < end at `rate` Hz and returns the updates.
@discardableResult
func feed(
    _ monitor: PostureMonitor,
    from start: TimeInterval,
    to end: TimeInterval,
    forward: Double = 0,
    lateral: Double = 0,
    rate: Double = 25
) -> [PostureUpdate] {
    var updates: [PostureUpdate] = []
    var i = 0
    while true {
        let t = ((start + Double(i) / rate) * 1e6).rounded() / 1e6
        if t >= end - 1e-9 {
            break
        }
        updates.append(monitor.process(Pose.sample(t, forward: forward, lateral: lateral)))
        i += 1
    }
    return updates
}

extension PostureState {
    /// Case name, matching the fixture JSON and the Python reference.
    var kindName: String {
        switch self {
        case .unavailable:
            return "unavailable"
        case .needsCalibration:
            return "needsCalibration"
        case .calibrating:
            return "calibrating"
        case .neutral:
            return "neutral"
        case .deviating:
            return "deviating"
        case .sustainedTilt:
            return "sustainedTilt"
        }
    }

    var direction: TiltDirection? {
        switch self {
        case let .deviating(direction, _), let .sustainedTilt(direction, _):
            return direction
        default:
            return nil
        }
    }

    var since: TimeInterval? {
        switch self {
        case let .deviating(_, since), let .sustainedTilt(_, since):
            return since
        default:
            return nil
        }
    }

    var progress: Double? {
        if case let .calibrating(progress) = self {
            return progress
        }
        return nil
    }
}

extension CalibrationOutcome {
    var name: String {
        switch self {
        case .succeeded:
            return "succeeded"
        case let .failed(failure):
            return failure.rawValue
        }
    }

    var failure: CalibrationFailure? {
        if case let .failed(failure) = self {
            return failure
        }
        return nil
    }
}
