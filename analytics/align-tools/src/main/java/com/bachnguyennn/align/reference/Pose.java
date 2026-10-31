package com.bachnguyennn.align.reference;

import static com.bachnguyennn.align.reference.Geometry.add;
import static com.bachnguyennn.align.reference.Geometry.gravityInHeadFrame;
import static com.bachnguyennn.align.reference.Geometry.quatFromAxisAngle;
import static com.bachnguyennn.align.reference.Geometry.quatFromRotationVector;
import static com.bachnguyennn.align.reference.Geometry.quatMul;
import static com.bachnguyennn.align.reference.Geometry.quatNormalized;
import static com.bachnguyennn.align.reference.Geometry.scale;

import com.bachnguyennn.align.reference.Geometry.Quat;
import com.bachnguyennn.align.reference.Geometry.Vec3;

/**
 * Head-pose model shared by the fixture generator, tests and evaluation.
 *
 * <p>Attitude q = Yaw(heading about world Z) * Tilt(rotation vector forward*forwardAxis +
 * lateral*lateralAxis, head frame) * Mount(pitch about forwardAxis, then roll about lateralAxis);
 * gravity in the device frame = q* (0, 0, -1) q. Axes always come from a HeadAxisConvention (by
 * default the AlignCore default, D-011), never hard-coded, so that "+20 deg forward" here means
 * TiltEstimate.forwardDegrees = +20 under the same convention.
 */
public final class Pose {

    public static final double RAD = Math.PI / 180.0;
    public static final Vec3 WORLD_UP = new Vec3(0.0, 0.0, 1.0);

    private Pose() {}

    public static Quat poseAttitude(double forwardDeg, double lateralDeg) {
        return poseAttitude(forwardDeg, lateralDeg, 0.0, 0.0, 0.0, null);
    }

    public static Quat poseAttitude(double forwardDeg, double lateralDeg, double headingDeg,
                                    double mountPitchDeg, double mountRollDeg) {
        return poseAttitude(forwardDeg, lateralDeg, headingDeg, mountPitchDeg, mountRollDeg, null);
    }

    /** {@code axes} null means {@link HeadAxisConvention#DEFAULT}. */
    public static Quat poseAttitude(double forwardDeg, double lateralDeg, double headingDeg,
                                    double mountPitchDeg, double mountRollDeg, HeadAxisConvention axes) {
        HeadAxisConvention a = axes != null ? axes : HeadAxisConvention.DEFAULT;
        Vec3 rv = add(scale(a.forwardAxis(), forwardDeg * RAD), scale(a.lateralAxis(), lateralDeg * RAD));
        Quat tilt = quatFromRotationVector(rv);
        Quat yaw = quatFromAxisAngle(WORLD_UP, headingDeg * RAD);
        Quat mount = quatMul(
                quatFromAxisAngle(a.forwardAxis(), mountPitchDeg * RAD),
                quatFromAxisAngle(a.lateralAxis(), mountRollDeg * RAD));
        return quatNormalized(quatMul(quatMul(yaw, tilt), mount));
    }

    public static MotionSample poseSample(double t) {
        return poseSample(t, 0.0, 0.0, true);
    }

    public static MotionSample poseSample(double t, double forwardDeg) {
        return poseSample(t, forwardDeg, 0.0, true);
    }

    public static MotionSample poseSample(double t, double forwardDeg, double lateralDeg) {
        return poseSample(t, forwardDeg, lateralDeg, true);
    }

    public static MotionSample poseSample(double t, double forwardDeg, double lateralDeg, boolean includeGravity) {
        return poseSample(t, forwardDeg, lateralDeg, 0.0, 0.0, 0.0, includeGravity, null);
    }

    public static MotionSample poseSample(double t, double forwardDeg, double lateralDeg, double headingDeg,
                                          double mountPitchDeg, double mountRollDeg, boolean includeGravity,
                                          HeadAxisConvention axes) {
        Quat q = poseAttitude(forwardDeg, lateralDeg, headingDeg, mountPitchDeg, mountRollDeg, axes);
        Vec3 g = includeGravity ? gravityInHeadFrame(q) : null;
        return new MotionSample(t, q, g);
    }
}
