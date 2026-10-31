package com.bachnguyennn.align.reference;

import static com.bachnguyennn.align.reference.Geometry.add;
import static com.bachnguyennn.align.reference.Geometry.cross;
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
        return poseAttitude(forwardDeg, lateralDeg, headingDeg, mountPitchDeg, mountRollDeg, 0.0, axes);
    }

    /**
     * With an earbud mount yaw (D-017): Mount = Yaw(mountYaw about the head's up axis,
     * {@code lateralAxis x forwardAxis}) * Pitch * Roll. A head nod then appears in the device
     * frame about an axis rotated by {@code mountYawDeg} (positive = a right-hand rotation about
     * the baseline gravity, i.e. toward the default lateral axis, which is the sign of
     * {@link AxisCalibrationService#signedYawDegrees}). {@code mountYawDeg = 0} gives exactly the
     * same quaternion as without it.
     */
    public static Quat poseAttitude(double forwardDeg, double lateralDeg, double headingDeg,
                                    double mountPitchDeg, double mountRollDeg, double mountYawDeg,
                                    HeadAxisConvention axes) {
        HeadAxisConvention a = axes != null ? axes : HeadAxisConvention.DEFAULT;
        Vec3 rv = add(scale(a.forwardAxis(), forwardDeg * RAD), scale(a.lateralAxis(), lateralDeg * RAD));
        Quat tilt = quatFromRotationVector(rv);
        Quat yaw = quatFromAxisAngle(WORLD_UP, headingDeg * RAD);
        Quat mount = mountAttitude(mountPitchDeg, mountRollDeg, mountYawDeg, a);
        return quatNormalized(quatMul(quatMul(yaw, tilt), mount));
    }

    /** The head-to-device mount rotation of {@link #poseAttitude}. */
    public static Quat mountAttitude(double mountPitchDeg, double mountRollDeg, double mountYawDeg,
                                     HeadAxisConvention axes) {
        HeadAxisConvention a = axes != null ? axes : HeadAxisConvention.DEFAULT;
        Quat mount = quatMul(
                quatFromAxisAngle(a.forwardAxis(), mountPitchDeg * RAD),
                quatFromAxisAngle(a.lateralAxis(), mountRollDeg * RAD));
        if (mountYawDeg != 0.0) {
            Vec3 headUp = cross(a.lateralAxis(), a.forwardAxis());
            mount = quatMul(quatFromAxisAngle(headUp, mountYawDeg * RAD), mount);
        }
        return mount;
    }

    /**
     * The true head axes as seen in the device frame for a given mount (what a perfect guided nod
     * learns): the head's forward/lateral axes rotated into the device frame and projected onto
     * the plane perpendicular to the neutral gravity.
     */
    public static HeadAxisConvention trueDeviceAxes(double mountPitchDeg, double mountRollDeg, double mountYawDeg,
                                                    HeadAxisConvention axes) {
        HeadAxisConvention a = axes != null ? axes : HeadAxisConvention.DEFAULT;
        Quat mountInverse = Geometry.quatConj(mountAttitude(mountPitchDeg, mountRollDeg, mountYawDeg, a));
        Vec3 g0 = gravityInHeadFrame(poseAttitude(0, 0, 0, mountPitchDeg, mountRollDeg, mountYawDeg, a));
        return new HeadAxisConvention(
                Tilt.baselinePlaneAxis(Geometry.quatRotate(mountInverse, a.forwardAxis()), g0),
                Tilt.baselinePlaneAxis(Geometry.quatRotate(mountInverse, a.lateralAxis()), g0));
    }

    /** Signed yaw (degrees) of {@link #trueDeviceAxes}' forward axis from {@code axes}' (see AxisCalibrationService). */
    public static double trueYawDegrees(double mountPitchDeg, double mountRollDeg, double mountYawDeg,
                                        HeadAxisConvention axes) {
        HeadAxisConvention a = axes != null ? axes : HeadAxisConvention.DEFAULT;
        Vec3 g0 = gravityInHeadFrame(poseAttitude(0, 0, 0, mountPitchDeg, mountRollDeg, mountYawDeg, a));
        return AxisCalibrationService.signedYawDegrees(
                trueDeviceAxes(mountPitchDeg, mountRollDeg, mountYawDeg, a).forwardAxis(), g0, a);
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
        return poseSample(t, forwardDeg, lateralDeg, headingDeg, mountPitchDeg, mountRollDeg, 0.0, includeGravity,
                axes);
    }

    public static MotionSample poseSample(double t, double forwardDeg, double lateralDeg, double headingDeg,
                                          double mountPitchDeg, double mountRollDeg, double mountYawDeg,
                                          boolean includeGravity, HeadAxisConvention axes) {
        Quat q = poseAttitude(forwardDeg, lateralDeg, headingDeg, mountPitchDeg, mountRollDeg, mountYawDeg, axes);
        Vec3 g = includeGravity ? gravityInHeadFrame(q) : null;
        return new MotionSample(t, q, g);
    }
}
