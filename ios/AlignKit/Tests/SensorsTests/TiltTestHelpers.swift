import AlignCore
import Foundation

/// Independent reference for the D-005 tilt idea, used only to check mock output:
/// the head rotation is the inverse of the rotation that takes the baseline head-frame
/// gravity to the current head-frame gravity, projected onto the convention's axes.
enum TiltReference {
    static let neutralGravity = Vector3(x: 0, y: 0, z: -1)

    static func headTiltDegrees(
        gravity: Vector3,
        baseline: Vector3 = neutralGravity,
        axes: HeadAxisConvention = .airPodsDefault
    ) -> (forward: Double, lateral: Double) {
        let g0 = baseline.normalized
        let g1 = gravity.normalized
        let axis = g0.cross(g1)
        let s = axis.length
        guard s > 1e-12 else { return (0, 0) }
        let angle = atan2(s, g0.dot(g1))
        let gravityRotation = axis * (angle / s)
        let headRotation = -gravityRotation
        let radiansToDegrees = 180 / Double.pi
        return (
            headRotation.dot(axes.forwardAxis.normalized) * radiansToDegrees,
            headRotation.dot(axes.lateralAxis.normalized) * radiansToDegrees
        )
    }
}
