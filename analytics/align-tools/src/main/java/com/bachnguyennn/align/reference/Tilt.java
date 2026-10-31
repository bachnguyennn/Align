package com.bachnguyennn.align.reference;

import static com.bachnguyennn.align.reference.Geometry.DEGREES_PER_RADIAN;
import static com.bachnguyennn.align.reference.Geometry.cross;
import static com.bachnguyennn.align.reference.Geometry.dot;
import static com.bachnguyennn.align.reference.Geometry.length;
import static com.bachnguyennn.align.reference.Geometry.neg;
import static com.bachnguyennn.align.reference.Geometry.normalized;
import static com.bachnguyennn.align.reference.Geometry.scale;
import static com.bachnguyennn.align.reference.Geometry.sub;

import com.bachnguyennn.align.reference.Geometry.Vec3;

/**
 * Tilt estimation from head-frame gravity relative to a baseline gravity (D-005).
 *
 * <p>Derivation (also in docs/research/algorithm-evaluation.md):
 *
 * <p>Let R0 be the head-to-world attitude at neutral and R1 = R0 * D the current attitude, where D
 * is the head's rotation expressed in the head frame (a body-frame increment). With world gravity
 * gw = (0, 0, -1) (Core Motion's Z-vertical reference frame), gravity seen in the head frame is
 * g0 = R0^T gw at neutral and g = R1^T gw = D^T R0^T gw = D^T g0 now. So the rotation that takes
 * g0 to g is D^T = D^-1: gravity in the head frame rotates <em>opposite</em> to the head. We
 * compute the minimal rotation taking g0 to g as a rotation vector r (axis g0 x g, angle
 * atan2(|g0 x g|, g0.g)) and the head rotation vector is -r. Rotation about g0 (heading/yaw) leaves
 * g unchanged and is therefore excluded by construction. For a pure flexion/lateral-bend D (axis
 * perpendicular to g0), the minimal rotation is exactly D^T, so -r equals D's rotation vector
 * exactly.
 *
 * <p>Axis projection: forward = (-r) . a_f and lateral = (-r) . a_l, in degrees. Because r is
 * always perpendicular to g0, the reference uses "baseline-plane axes": each configured axis is
 * first projected onto the plane perpendicular to g0 and renormalized. When the configured axis is
 * already perpendicular to g0 (e.g. g0 = -z with axes x/y) this is identical to the plain
 * projection. When the earbud sits pitched or rolled in the ear (g0 not exactly -z), the true
 * flexion/lateral axes are horizontal at neutral, i.e. perpendicular to g0, and the plain
 * projection under-reads by cos(offset); the baseline-plane projection removes that error.
 * {@code orthogonalizeAxes = false} gives the plain projection (used only by the evaluation).
 */
public final class Tilt {

    /** Below this cross-product length the two gravity vectors are treated as parallel. */
    public static final double PARALLEL_EPSILON = 1e-12;
    /** A configured axis closer than ~0.06 degrees to the baseline gravity cannot be projected. */
    public static final double AXIS_DEGENERACY_EPSILON = 1e-3;

    private Tilt() {}

    /** Minimal rotation taking unit vector {@code fromUnit} to {@code toUnit}, as axis * angle (radians). */
    public static Vec3 rotationVector(Vec3 fromUnit, Vec3 toUnit) {
        Vec3 c = cross(fromUnit, toUnit);
        double s = length(c);
        double d = dot(fromUnit, toUnit);
        double angle = StrictMath.atan2(s, d);
        if (s < PARALLEL_EPSILON) {
            // Parallel (angle 0) or antiparallel (axis undefined): report no directional rotation.
            return new Vec3(0.0, 0.0, 0.0);
        }
        return scale(c, angle / s);
    }

    /** Projects {@code axis} onto the plane perpendicular to the baseline gravity and renormalizes. */
    public static Vec3 baselinePlaneAxis(Vec3 axis, Vec3 baselineUnit) {
        Vec3 a = normalized(axis);
        Vec3 p = sub(a, scale(baselineUnit, dot(a, baselineUnit)));
        double n = length(p);
        if (n < AXIS_DEGENERACY_EPSILON) {
            return a;
        }
        return scale(p, 1.0 / n);
    }

    public static TiltEstimate estimateTilt(double timestamp, Vec3 gravityUnit, Vec3 baselineUnit,
                                            HeadAxisConvention axes) {
        return estimateTilt(timestamp, gravityUnit, baselineUnit, axes, true);
    }

    public static TiltEstimate estimateTilt(double timestamp, Vec3 gravityUnit, Vec3 baselineUnit,
                                            HeadAxisConvention axes, boolean orthogonalizeAxes) {
        Vec3 baseline = normalized(baselineUnit);
        Vec3 r = rotationVector(baseline, gravityUnit);
        Vec3 head = neg(r);
        Vec3 forwardAxis;
        Vec3 lateralAxis;
        if (orthogonalizeAxes) {
            forwardAxis = baselinePlaneAxis(axes.forwardAxis(), baseline);
            lateralAxis = baselinePlaneAxis(axes.lateralAxis(), baseline);
        } else {
            forwardAxis = normalized(axes.forwardAxis());
            lateralAxis = normalized(axes.lateralAxis());
        }
        double total = StrictMath.atan2(length(cross(baseline, gravityUnit)), dot(baseline, gravityUnit));
        return new TiltEstimate(
                timestamp,
                dot(head, forwardAxis) * DEGREES_PER_RADIAN,
                dot(head, lateralAxis) * DEGREES_PER_RADIAN,
                total * DEGREES_PER_RADIAN);
    }
}
