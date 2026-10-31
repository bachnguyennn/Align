import Foundation
import AlignCore

/// Tilt estimation from head-frame gravity relative to a baseline gravity (D-005).
/// Mirrors `Tilt` in `analytics/align-tools`.
///
/// Derivation: let `R0` be the head-to-world attitude at neutral and `R1 = R0 * D` the current
/// one, where `D` is the head's rotation expressed in the head frame. With world gravity
/// `gw = (0, 0, -1)` (Core Motion's Z-vertical reference), the head-frame gravity is
/// `g0 = R0ᵀ gw` at neutral and `g = R1ᵀ gw = Dᵀ g0` now. The rotation taking `g0` to `g` is
/// therefore `D⁻¹`: gravity seen in the head frame rotates opposite to the head. We compute the
/// minimal rotation `r` taking `g0` to `g` (axis `g0 × g`, angle `atan2(|g0 × g|, g0 · g)`); the
/// head rotation vector is `-r`. Rotation about `g0` (heading) leaves `g` unchanged, so heading is
/// excluded by construction.
///
/// Axis projection uses "baseline-plane axes": each configured axis is projected onto the plane
/// perpendicular to `g0` and renormalized before taking the dot product. `r` is always
/// perpendicular to `g0`, and the true flexion / lateral-bend axes are horizontal at neutral, so
/// this removes the `cos(offset)` under-reading caused by an earbud sitting pitched or rolled in
/// the ear. It is identical to the plain projection when the axes are already perpendicular to
/// `g0`.
///
/// `PostureMonitor` passes its `effectiveAxes`: the axes learned from a guided nod (D-017), which
/// also remove earbud yaw (forward↔lateral crosstalk), or else `configuration.axes`.
public enum TiltEstimator {
    /// Below this cross-product length the two gravity vectors are treated as parallel.
    static let parallelEpsilon: Double = 1e-12
    /// A configured axis closer than ~0.06° to the baseline gravity cannot be projected.
    static let axisDegeneracyEpsilon: Double = 1e-3

    /// Minimal rotation taking unit vector `from` to unit vector `to`, as axis × angle (radians).
    public static func rotationVector(from: Vector3, to: Vector3) -> Vector3 {
        let c = from.cross(to)
        let s = c.length
        let d = from.dot(to)
        let angle = atan2(s, d)
        if s < parallelEpsilon {
            // Parallel (angle 0) or antiparallel (axis undefined): no directional rotation.
            return .zero
        }
        return c * (angle / s)
    }

    /// `axis` projected onto the plane perpendicular to `baseline` (unit) and renormalized.
    public static func baselinePlaneAxis(_ axis: Vector3, baseline: Vector3) -> Vector3 {
        let a = axis.normalized
        let p = a - baseline * a.dot(baseline)
        let n = p.length
        if n < axisDegeneracyEpsilon {
            return a
        }
        return p * (1.0 / n)
    }

    /// Angle between two vectors in degrees, numerically stable for small angles.
    public static func angleDegrees(between a: Vector3, and b: Vector3) -> Double {
        atan2(a.cross(b).length, a.dot(b)) * PostureDetectionConstants.degreesPerRadian
    }

    /// Tilt of unit head-frame `gravity` relative to the baseline gravity.
    public static func estimate(
        timestamp: TimeInterval,
        gravity: Vector3,
        baseline: Vector3,
        axes: HeadAxisConvention
    ) -> TiltEstimate {
        let g0 = baseline.normalized
        let r = rotationVector(from: g0, to: gravity)
        let head = -r
        let forwardAxis = baselinePlaneAxis(axes.forwardAxis, baseline: g0)
        let lateralAxis = baselinePlaneAxis(axes.lateralAxis, baseline: g0)
        let total = atan2(g0.cross(gravity).length, g0.dot(gravity))
        return TiltEstimate(
            timestamp: timestamp,
            forwardDegrees: head.dot(forwardAxis) * PostureDetectionConstants.degreesPerRadian,
            lateralDegrees: head.dot(lateralAxis) * PostureDetectionConstants.degreesPerRadian,
            totalDegrees: total * PostureDetectionConstants.degreesPerRadian
        )
    }

    /// Gravity (unit, in g) in the head frame for a head-to-world attitude in a Z-up world.
    /// Used only when a sample has no `gravity`.
    public static func gravity(fromAttitude attitude: Quaternion) -> Vector3 {
        attitude.normalized.conjugate.rotate(Vector3(x: 0, y: 0, z: -1))
    }
}
