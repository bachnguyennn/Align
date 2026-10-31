package com.bachnguyennn.align.reference;

import static com.bachnguyennn.align.reference.Approx.assertApprox;
import static com.bachnguyennn.align.reference.Approx.assertApproxRel;
import static com.bachnguyennn.align.reference.Geometry.angleBetweenDegrees;
import static com.bachnguyennn.align.reference.Geometry.cross;
import static com.bachnguyennn.align.reference.Geometry.gravityInHeadFrame;
import static com.bachnguyennn.align.reference.Geometry.normalized;
import static com.bachnguyennn.align.reference.Geometry.quatFromAxisAngle;
import static com.bachnguyennn.align.reference.Geometry.quatRotate;
import static com.bachnguyennn.align.reference.Geometry.scale;
import static com.bachnguyennn.align.reference.Pose.poseAttitude;
import static com.bachnguyennn.align.reference.Tilt.baselinePlaneAxis;
import static com.bachnguyennn.align.reference.Tilt.estimateTilt;
import static com.bachnguyennn.align.reference.Tilt.rotationVector;
import static org.junit.jupiter.api.Assertions.assertEquals;

import com.bachnguyennn.align.reference.Geometry.Quat;
import com.bachnguyennn.align.reference.Geometry.Vec3;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.ValueSource;

/** Port of tests/test_geometry_tilt.py. */
class GeometryTiltTest {

    private static final HeadAxisConvention AXES = HeadAxisConvention.DEFAULT;
    private static final double RAD = Math.PI / 180;

    private static TiltEstimate tiltFor(double forward, double lateral, double heading, double pitch, double roll,
                                        boolean orthogonalize) {
        Vec3 g0 = gravityInHeadFrame(poseAttitude(0, 0, 0, pitch, roll));
        Vec3 g = gravityInHeadFrame(poseAttitude(forward, lateral, heading, pitch, roll));
        return estimateTilt(0.0, g, g0, AXES, orthogonalize);
    }

    private static TiltEstimate tiltFor(double forward, double lateral) {
        return tiltFor(forward, lateral, 0.0, 0.0, 0.0, true);
    }

    @Test
    void defaultAxisConventionIsD011AndRightHanded() {
        // D-011: head frame +X right ear, +Y nose, +Z up; chin-down axis x right-ear-down axis = down.
        assertEquals(new Vec3(-1.0, 0.0, 0.0), AXES.forwardAxis());
        assertEquals(new Vec3(0.0, 1.0, 0.0), AXES.lateralAxis());
        Vec3 c = cross(AXES.forwardAxis(), AXES.lateralAxis());
        assertApprox(new Vec3(0.0, 0.0, -1.0), c, 1e-12);
    }

    @Test
    void gravityCrossCheckValuesUnderDefaultConvention() {
        // +20 deg chin-down: nose tips toward the floor, gravity gains +Y: (0, +sin20, -cos20).
        Vec3 g = gravityInHeadFrame(quatFromAxisAngle(AXES.forwardAxis(), 20 * RAD));
        assertApprox(new Vec3(0.0, Math.sin(20 * RAD), -Math.cos(20 * RAD)), g, 1e-12);
        assertApprox(new Vec3(0.0, 0.342, -0.940), g, 1e-3);
        // +20 deg right-ear-down: the right ear (+X) drops, gravity gains +X: (+sin20, 0, -cos20).
        g = gravityInHeadFrame(quatFromAxisAngle(AXES.lateralAxis(), 20 * RAD));
        assertApprox(new Vec3(Math.sin(20 * RAD), 0.0, -Math.cos(20 * RAD)), g, 1e-12);
        assertApprox(new Vec3(0.342, 0.0, -0.940), g, 1e-3);
        // And the estimator reads both as +20 in their direction.
        assertApprox(20, tiltFor(20, 0).forwardDegrees(), 1e-9);
        assertApprox(20, tiltFor(0, 20).lateralDegrees(), 1e-9);
    }

    @Test
    void poseModelReadsAxesFromConfiguration() {
        // A non-default convention must be honoured end to end (nothing hard-coded).
        HeadAxisConvention custom = new HeadAxisConvention(new Vec3(0.0, 1.0, 0.0), new Vec3(1.0, 0.0, 0.0));
        Vec3 g0 = gravityInHeadFrame(poseAttitude(0, 0, 0, 0, 0, custom));
        Vec3 g = gravityInHeadFrame(poseAttitude(17, -6, 0, 0, 0, custom));
        TiltEstimate t = estimateTilt(0.0, g, g0, custom);
        assertApprox(17, t.forwardDegrees(), 1e-9);
        assertApprox(-6, t.lateralDegrees(), 1e-9);
    }

    @Test
    void quaternionRotateMatchesRightHandRule() {
        Quat q = quatFromAxisAngle(new Vec3(0, 0, 1), Math.PI / 2);
        Vec3 v = quatRotate(q, new Vec3(1, 0, 0));
        assertApprox(0, v.x(), 1e-12);
        assertApprox(1, v.y());
        assertApprox(0, v.z(), 1e-12);
    }

    @Test
    void signDerivationForwardRotationGivesPositiveForward() {
        // The derivation check requested in the brief: rotate the head +20 deg about forwardAxis
        // (Z-up world), gravity in head frame = q.conjugate.rotate((0,0,-1)).
        Quat q = quatFromAxisAngle(AXES.forwardAxis(), 20 * RAD);
        Vec3 g = gravityInHeadFrame(q);
        Vec3 g0 = new Vec3(0.0, 0.0, -1.0);
        // Gravity in the head frame rotates the *opposite* way: by -20 deg about forwardAxis.
        Vec3 r = rotationVector(g0, g);
        assertApprox(scale(AXES.forwardAxis(), -20 * RAD), r, 1e-12);
        TiltEstimate t = estimateTilt(0.0, g, g0, AXES);
        assertApprox(20.0, t.forwardDegrees(), 1e-9);
        assertApprox(0.0, t.lateralDegrees(), 1e-9);
        assertApprox(20.0, t.totalDegrees(), 1e-9);
    }

    @ParameterizedTest(name = "forward={0}, lateral={1}")
    @CsvSource({"20,0", "-25,0", "0,18", "0,-12", "15,10", "-10,-20"})
    void pureFlexionAndLateralBendAreRecoveredExactly(double forward, double lateral) {
        TiltEstimate t = tiltFor(forward, lateral);
        assertApprox(forward, t.forwardDegrees(), 1e-9);
        assertApprox(lateral, t.lateralDegrees(), 1e-9);
        assertApprox(Math.hypot(forward, lateral), t.totalDegrees(), 1e-9);
    }

    @ParameterizedTest(name = "heading={0}")
    @ValueSource(doubles = {0, 37, 90, 180, -135})
    void headingIsExcluded(double heading) {
        TiltEstimate t = tiltFor(20, 5, heading, 0.0, 0.0, true);
        assertApprox(20, t.forwardDegrees(), 1e-9);
        assertApprox(5, t.lateralDegrees(), 1e-9);
    }

    @Test
    void mountPitchIsExactWithBaselinePlaneAxesButNotPlainProjection() {
        TiltEstimate ortho = tiltFor(0, 20, 0.0, 15, 0.0, true);
        TiltEstimate plain = tiltFor(0, 20, 0.0, 15, 0.0, false);
        assertApprox(20, ortho.lateralDegrees(), 1e-9);
        assertApprox(20 * Math.cos(15 * RAD), plain.lateralDegrees(), 1e-9);
    }

    @Test
    void axesAlreadyPerpendicularToBaselineAreUnchanged() {
        Vec3 g0 = new Vec3(0, 0, -1);
        assertApprox(AXES.forwardAxis(), baselinePlaneAxis(AXES.forwardAxis(), g0));
    }

    @Test
    void degenerateAxisFallsBackToConfiguredAxis() {
        Vec3 g0 = new Vec3(0, 0, -1);
        assertApprox(new Vec3(0, 0, 1), baselinePlaneAxis(new Vec3(0, 0, 1), g0));
    }

    @Test
    void rotationVectorParallelAndTinyAngles() {
        Vec3 g = new Vec3(0, 0, -1);
        assertEquals(new Vec3(0, 0, 0), rotationVector(g, g));
        Vec3 tiny = normalized(new Vec3(1e-9, 0, -1));
        Vec3 r = rotationVector(g, tiny);
        assertApproxRel(1e-9, Math.abs(r.y()), 1e-3);
    }

    @Test
    void angleBetweenSmallAngleIsStable() {
        Vec3 a = new Vec3(0, 0, -1);
        Vec3 b = normalized(new Vec3(Math.tan(0.001 * RAD), 0, -1));
        assertApproxRel(0.001, angleBetweenDegrees(a, b), 1e-6);
    }
}
