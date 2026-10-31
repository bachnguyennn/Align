import Foundation
import AlignCore

/// Quick, calibration-free tilt estimate for the Diagnostics axis check (D-005 method):
/// the rotation taking the captured neutral gravity to the current gravity (both in the head
/// frame) is expressed as a rotation vector. The head rotates opposite to the gravity vector seen
/// in its own frame, so the head rotation vector is the negation; it is projected onto the
/// convention's forward and lateral axes.
///
/// This exists only so a person can check the signs on hardware (S-05). The PostureMonitor tilt
/// shown next to it is the authoritative value; if the two disagree, report it.
enum AxisCheck {
    struct Result: Equatable {
        var forwardDegrees: Double
        var lateralDegrees: Double
        var totalDegrees: Double
    }

    static func tilt(neutralGravity: Vector3, currentGravity: Vector3, axes: HeadAxisConvention) -> Result? {
        let from = neutralGravity.normalized
        let to = currentGravity.normalized
        guard from.length > 0, to.length > 0 else { return nil }
        let cosine = min(1, max(-1, from.dot(to)))
        let angle = acos(cosine)
        let axis = from.cross(to)
        guard axis.length > 1e-9, angle > 1e-9 else {
            return Result(forwardDegrees: 0, lateralDegrees: 0, totalDegrees: 0)
        }
        // Rotation vector of the gravity direction, then negate for the head's own rotation.
        let headRotation = -(axis.normalized * angle)
        let degreesPerRadian = 180 / Double.pi
        return Result(
            forwardDegrees: headRotation.dot(axes.forwardAxis.normalized) * degreesPerRadian,
            lateralDegrees: headRotation.dot(axes.lateralAxis.normalized) * degreesPerRadian,
            totalDegrees: angle * degreesPerRadian
        )
    }
}
