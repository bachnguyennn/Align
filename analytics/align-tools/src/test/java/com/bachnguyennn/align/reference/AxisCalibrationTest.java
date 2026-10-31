package com.bachnguyennn.align.reference;

import static com.bachnguyennn.align.reference.Approx.assertApprox;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.bachnguyennn.align.reference.AxisCalibrationService.AxisCalibrationStep;
import com.bachnguyennn.align.reference.AxisCalibrationService.Fit;
import com.bachnguyennn.align.reference.AxisCalibrationService.LineFit;
import com.bachnguyennn.align.reference.Geometry.Vec3;
import com.bachnguyennn.align.reference.PostureState.Kind;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import org.junit.jupiter.api.Test;

/**
 * Guided-nod axis calibration (D-017): {@link AxisCalibrationService} and the monitor API. Mirrored
 * by the Swift {@code AxisCalibrationTests}.
 */
class AxisCalibrationTest {

    private static final double RATE = 25.0;
    private static final double DT = 1.0 / RATE;
    private static final double RAD = Math.PI / 180.0;
    private static final Vec3 DOWN = new Vec3(0.0, 0.0, -1.0);

    /** A noise-free head pose seen through an earbud mounted with pitch/roll/yaw (degrees). */
    private record Mount(double pitch, double roll, double yaw) {
        static final Mount NONE = new Mount(0, 0, 0);

        MotionSample sample(double t, double forward, double lateral, double heading) {
            return Pose.poseSample(t, forward, lateral, heading, pitch, roll, yaw, true, null);
        }
    }

    /** Nod profile: 1 s down to {@code depth}, 1 s back, then neutral (relative seconds). */
    private static double nod(double rel, double depth) {
        if (rel < 0) {
            return 0.0;
        }
        if (rel < 1.0) {
            return depth * rel;
        }
        if (rel < 2.0) {
            return depth * (2.0 - rel);
        }
        return 0.0;
    }

    private interface Profile {
        double[] at(double rel);  // {forward, lateral}
    }

    /** Feeds samples for start ≤ t < end following {@code profile} (relative to start). */
    private static List<PostureUpdate> feed(PostureMonitor m, Mount mount, double start, double end, Profile profile) {
        List<PostureUpdate> out = new ArrayList<>();
        for (int i = 0; ; i++) {
            double t = PythonFormat.round(start + i / RATE, 6);
            if (t >= end - 1e-9) {
                break;
            }
            double[] pose = profile.at(t - start);
            out.add(m.process(mount.sample(t, pose[0], pose[1], 17.0 * i / RATE)));
        }
        return out;
    }

    private static List<PostureUpdate> hold(PostureMonitor m, Mount mount, double start, double end,
                                            double forward, double lateral) {
        return feed(m, mount, start, end, rel -> new double[] {forward, lateral});
    }

    /** Neutral-calibrated monitor (0 ≤ t ≤ 10 s) for the given mount; next sample at t = 10.04. */
    private static PostureMonitor calibrated(Mount mount, PostureConfiguration config) {
        PostureMonitor m = new PostureMonitor(config);
        m.beginCalibration();
        hold(m, mount, 0.0, 10.0 + DT, 0.0, 0.0);
        assertNotNull(m.baseline());
        assertEquals(1, m.baseline().version());
        assertNull(m.baseline().learnedAxes());
        return m;
    }

    private static PostureMonitor calibrated(Mount mount) {
        return calibrated(mount, PostureConfiguration.DEFAULT);
    }

    private static List<AxisCalibrationOutcome> axisOutcomes(List<PostureUpdate> updates) {
        return updates.stream().map(PostureUpdate::axisCalibrationOutcome).filter(Objects::nonNull).toList();
    }

    private static double yaw(PostureMonitor m) {
        return AxisCalibrationService.signedYawDegrees(m.effectiveAxes().forwardAxis(), m.baseline().gravity(),
                m.configuration().axes());
    }

    // MARK: - Fit

    /** For the default axes and baseline gravity (0, 0, -1), lateral = g x forward reproduces (0, 1, 0). */
    @Test
    void fitReproducesDefaultAxesForANodAboutTheDefaultForwardAxis() {
        List<Vec3> rotations = new ArrayList<>();
        for (double a : new double[] {4, 10, 20, 10, 4, -6}) {
            rotations.add(Geometry.scale(HeadAxisConvention.DEFAULT.forwardAxis(), a * RAD));
        }
        for (LineFit method : LineFit.values()) {
            Fit fit = AxisCalibrationService.fit(rotations, DOWN, HeadAxisConvention.DEFAULT, method);
            assertApprox(new Vec3(-1, 0, 0), fit.axes().forwardAxis(), 1e-12);
            assertApprox(new Vec3(0, 1, 0), fit.axes().lateralAxis(), 1e-12);
            assertApprox(0.0, fit.yawDegrees(), 1e-9);
            assertApprox(0.0, fit.offAxisRatio(), 1e-12);
            assertEquals(6, fit.samplesUsed());
        }
        assertEquals(new Vec3(0, 1, 0), Geometry.cross(DOWN, HeadAxisConvention.DEFAULT.forwardAxis()));
    }

    @Test
    void fitSignFollowsDefaultForNodDownOrUpAndMeasuresYaw() {
        Vec3 axis = new Vec3(-Math.cos(30 * RAD), Math.sin(30 * RAD), 0);  // default forward yawed by +30 deg
        for (double sign : new double[] {1, -1}) {
            List<Vec3> rotations = List.of(Geometry.scale(axis, sign * 15 * RAD), Geometry.scale(axis, sign * 25 * RAD));
            Fit fit = AxisCalibrationService.fit(rotations, DOWN, HeadAxisConvention.DEFAULT, LineFit.PRINCIPAL_AXIS);
            assertApprox(axis, fit.axes().forwardAxis(), 1e-12);
            assertApprox(30.0, fit.yawDegrees(), 1e-9);
            assertTrue(Geometry.dot(fit.axes().forwardAxis(), HeadAxisConvention.DEFAULT.forwardAxis()) > 0);
        }
    }

    @Test
    void lShapedMotionHasALargeOffAxisRatio() {
        Vec3 f = HeadAxisConvention.DEFAULT.forwardAxis();
        Vec3 l = HeadAxisConvention.DEFAULT.lateralAxis();
        List<Vec3> rotations = List.of(Geometry.scale(f, 20 * RAD), Geometry.scale(f, 10 * RAD),
                Geometry.scale(l, 15 * RAD), Geometry.scale(l, 8 * RAD));
        Fit fit = AxisCalibrationService.fit(rotations, DOWN, HeadAxisConvention.DEFAULT, LineFit.PRINCIPAL_AXIS);
        assertTrue(fit.offAxisRatio() > 0.35, "ratio " + fit.offAxisRatio());
    }

    @Test
    void floorAndReturnLevelsAreCappedAtHalfTheMinimumNod() {
        assertEquals(3.0, AxisCalibrationService.floorDegrees(12.0));
        assertEquals(5.0, AxisCalibrationService.returnDegrees(12.0));
        assertEquals(2.0, AxisCalibrationService.floorDegrees(4.0));
        assertEquals(2.0, AxisCalibrationService.returnDegrees(4.0));
    }

    // MARK: - Service

    @Test
    void serviceReportsProgressAndFinishesWhenTheHeadReturns() {
        AxisCalibrationService s = new AxisCalibrationService();
        PostureConfiguration cfg = PostureConfiguration.DEFAULT;
        s.begin();
        assertEquals(0.0, s.progress(cfg.axisCalibrationDuration()));
        AxisCalibrationStep step = null;
        int i = 0;
        for (; i < 400; i++) {
            double t = i / RATE;
            Vec3 g = Geometry.gravityInHeadFrame(Pose.poseAttitude(nod(t - 1.0, 20.0), 0.0));
            step = s.add(g, t, DOWN, cfg);
            if (step.finished()) {
                break;
            }
            if (i == 25) {
                assertApprox(1.0 / 8.0, step.progress());
            }
        }
        assertNotNull(step);
        assertTrue(step.finished());
        assertNull(step.failure());
        assertFalse(s.isActive());
        // Back within 5 deg of neutral on the way up: 20 * (2 - rel) <= 5 at rel >= 1.75, i.e. t = 2.76.
        assertApprox(2.76, i / RATE, DT);
        assertApprox(new Vec3(-1, 0, 0), step.axes().forwardAxis(), 1e-9);
    }

    @Test
    void serviceTimesOutWithoutANod() {
        AxisCalibrationService s = new AxisCalibrationService();
        s.begin();
        AxisCalibrationStep step = null;
        int i = 0;
        for (; i < 400 && (step == null || !step.finished()); i++) {
            step = s.add(Geometry.gravityInHeadFrame(Pose.poseAttitude(2.0, 1.0)), i / RATE, DOWN,
                    PostureConfiguration.DEFAULT);
        }
        assertEquals(AxisCalibrationFailure.NO_NOD_DETECTED, step.failure());
        assertEquals(201, i);  // t = 0 .. 8.0 inclusive
    }

    // MARK: - Monitor

    @Test
    void needsBaselineIsReportedOnTheNextUpdateOnly() {
        PostureMonitor m = new PostureMonitor();
        m.beginAxisCalibration();
        assertEquals(Kind.UNAVAILABLE, m.state().kind());
        PostureUpdate u = m.process(Mount.NONE.sample(0.0, 0, 0, 0));
        assertNotNull(u.axisCalibrationOutcome());
        assertEquals(AxisCalibrationFailure.NEEDS_BASELINE, u.axisCalibrationOutcome().failure());
        assertEquals(Kind.NEEDS_CALIBRATION, u.state().kind());
        assertEquals(List.of(), axisOutcomes(hold(m, Mount.NONE, DT, 2.0, 0, 0)));

        PostureMonitor viaInterrupt = new PostureMonitor();
        viaInterrupt.beginAxisCalibration();
        assertEquals(AxisCalibrationFailure.NEEDS_BASELINE, viaInterrupt.interrupt(1.0).axisCalibrationOutcome().failure());
    }

    @Test
    void noNodDetectedAfterTheDurationKeepsDefaultAxes() {
        PostureMonitor m = calibrated(Mount.NONE);
        m.beginAxisCalibration();
        List<PostureUpdate> ups = hold(m, Mount.NONE, 10.04, 20.0, 1.0, 0.5);
        List<PostureUpdate> withOutcome = ups.stream().filter(u -> u.axisCalibrationOutcome() != null).toList();
        assertEquals(1, withOutcome.size());
        assertEquals(AxisCalibrationFailure.NO_NOD_DETECTED, withOutcome.get(0).axisCalibrationOutcome().failure());
        assertApprox(18.04, withOutcome.get(0).timestamp(), 1e-6);
        assertEquals(HeadAxisConvention.DEFAULT, m.effectiveAxes());
        assertNull(m.baseline().learnedAxes());
        assertEquals(1, m.baseline().version());
        assertEquals(Kind.NEUTRAL, m.state().kind());
    }

    @Test
    void sidewaysTiltIsRejectedAsInconsistentMotion() {
        PostureMonitor m = calibrated(Mount.NONE);
        m.beginAxisCalibration();
        List<PostureUpdate> ups = feed(m, Mount.NONE, 10.04, 16.0, rel -> new double[] {0.0, nod(rel - 0.5, 20.0)});
        List<AxisCalibrationOutcome> outcomes = axisOutcomes(ups);
        assertEquals(1, outcomes.size());
        assertEquals(AxisCalibrationFailure.INCONSISTENT_MOTION, outcomes.get(0).failure());
        assertEquals(HeadAxisConvention.DEFAULT, m.effectiveAxes());
        assertEquals(1, m.baseline().version());
    }

    @Test
    void diagonalMotionBeyondMaxYawIsRejected() {
        PostureMonitor m = calibrated(Mount.NONE);
        m.beginAxisCalibration();
        // 20 deg nod along an axis 60 deg from the default forward axis.
        List<PostureUpdate> ups = feed(m, Mount.NONE, 10.04, 16.0, rel -> new double[] {
                nod(rel - 0.5, 20.0) * Math.cos(60 * RAD), nod(rel - 0.5, 20.0) * Math.sin(60 * RAD)});
        assertEquals(AxisCalibrationFailure.INCONSISTENT_MOTION, axisOutcomes(ups).get(0).failure());
    }

    /** Noise-free yawed earbud (25 deg, plus the generator's 8/-3 pitch/roll): yaw recovered within 1 deg. */
    @Test
    void yawedEarbudIsRecoveredAndRemovesCrosstalk() {
        Mount mount = new Mount(8.0, -3.0, 25.0);
        PostureMonitor m = calibrated(mount);
        m.beginAxisCalibration();
        assertEquals(Kind.CALIBRATING, m.state().kind());
        List<PostureUpdate> ups = feed(m, mount, 10.04, 16.0, rel -> new double[] {nod(rel - 0.5, 20.0), 0.0});
        List<AxisCalibrationOutcome> outcomes = axisOutcomes(ups);
        assertEquals(1, outcomes.size());
        assertTrue(outcomes.get(0).succeeded());
        assertEquals(outcomes.get(0).axes(), m.baseline().learnedAxes());
        assertEquals(m.baseline().learnedAxes(), m.effectiveAxes());
        assertEquals(2, m.baseline().version());
        double trueYaw = Pose.trueYawDegrees(8.0, -3.0, 25.0, null);
        assertApprox(trueYaw, yaw(m), 1e-6);
        assertApprox(25.0, yaw(m), 1.0);

        // With learned axes, a 20 deg forward hold reads 20 deg forward and no lateral.
        List<PostureUpdate> held = hold(m, mount, 16.0, 20.0, 20.0, 0.0);
        TiltEstimate tilt = held.get(held.size() - 1).tilt();
        assertApprox(20.0, tilt.forwardDegrees(), 0.02);  // filter residual 20 exp(-4 / 0.5)
        assertApprox(0.0, tilt.lateralDegrees(), 1e-3);
        // With default axes the same pose shows 8.45 deg of lateral crosstalk.
        TiltEstimate plain = Tilt.estimateTilt(0, Geometry.gravityInHeadFrame(Pose.poseAttitude(20, 0, 0, 8, -3, 25, null)),
                m.baseline().gravity(), HeadAxisConvention.DEFAULT);
        assertApprox(20.0 * Math.sin(25 * RAD), plain.lateralDegrees(), 0.05);
    }

    @Test
    void nodUpWorksAndKeepsTheDefaultSign() {
        Mount mount = new Mount(8.0, -3.0, -15.0);
        PostureMonitor m = calibrated(mount);
        m.beginAxisCalibration();
        List<PostureUpdate> ups = feed(m, mount, 10.04, 16.0, rel -> new double[] {nod(rel - 0.5, -20.0), 0.0});
        assertTrue(axisOutcomes(ups).get(0).succeeded());
        assertApprox(Pose.trueYawDegrees(8.0, -3.0, -15.0, null), yaw(m), 1e-6);
        assertTrue(Geometry.dot(m.effectiveAxes().forwardAxis(), HeadAxisConvention.DEFAULT.forwardAxis()) > 0);
        List<PostureUpdate> held = hold(m, mount, 16.0, 20.0, -25.0, 0.0);
        assertApprox(-25.0, held.get(held.size() - 1).tilt().forwardDegrees(), 0.02);
        assertEquals(TiltDirection.BACKWARD, held.get(held.size() - 1).state().direction());
    }

    @Test
    void interruptAndGapFailWithSensorInterrupted() {
        PostureMonitor m = calibrated(Mount.NONE);
        m.beginAxisCalibration();
        feed(m, Mount.NONE, 10.04, 11.0, rel -> new double[] {nod(rel, 20.0), 0.0});
        PostureUpdate u = m.interrupt(11.0);
        assertEquals(AxisCalibrationFailure.SENSOR_INTERRUPTED, u.axisCalibrationOutcome().failure());
        assertEquals(Kind.UNAVAILABLE, u.state().kind());
        assertNull(m.baseline().learnedAxes());

        m.beginAxisCalibration();
        hold(m, Mount.NONE, 12.0, 13.0, 0, 0);
        PostureUpdate afterGap = m.process(Mount.NONE.sample(15.0, 0, 0, 0));
        assertEquals(AxisCalibrationFailure.SENSOR_INTERRUPTED, afterGap.axisCalibrationOutcome().failure());
        assertEquals(Kind.NEUTRAL, afterGap.state().kind());
    }

    @Test
    void stateIsCalibratingWithNoDetectorRemindersOrEpisodes() {
        PostureMonitor m = calibrated(Mount.NONE, PostureConfiguration.DEFAULT.replacing(
                b -> b.sustainedDuration(1.0).axisCalibrationDuration(8.0)));
        m.beginAxisCalibration();
        List<PostureUpdate> ups = hold(m, Mount.NONE, 10.04, 18.05, 25.0, 0.0);
        for (PostureUpdate u : ups.subList(0, ups.size() - 1)) {
            assertEquals(Kind.CALIBRATING, u.state().kind());
            assertNull(u.reminder());
            assertNull(u.completedEpisode());
        }
        assertApprox(0.5, ups.get(100).state().progress(), 1e-9);
        // The head never returned, so the attempt ends at the duration and is fitted (a held nod).
        assertEquals(1, axisOutcomes(ups).size());
    }

    @Test
    void beginAxisCalibrationClosesAnOpenEpisode() {
        PostureMonitor m = calibrated(Mount.NONE);
        hold(m, Mount.NONE, 10.04, 45.0, 25.0, 0.0);
        assertEquals(Kind.SUSTAINED_TILT, m.state().kind());
        Double last = m.lastProcessedTimestamp();
        m.beginAxisCalibration();
        PostureUpdate u = m.process(Mount.NONE.sample(45.0, 25.0, 0, 0));
        assertNotNull(u.completedEpisode());
        assertEquals(last, u.completedEpisode().endTimestamp());
        assertEquals(Kind.CALIBRATING, u.state().kind());
    }

    @Test
    void neutralRecalibrationClearsLearnedAxesAndVersionsIncrement() {
        Mount mount = new Mount(0, 0, 20);
        PostureMonitor m = calibrated(mount);
        m.beginAxisCalibration();
        feed(m, mount, 10.04, 16.0, rel -> new double[] {nod(rel - 0.5, 20.0), 0.0});
        assertNotNull(m.baseline().learnedAxes());
        assertEquals(2, m.baseline().version());
        m.beginCalibration();
        List<PostureUpdate> ups = hold(m, mount, 16.0, 26.5, 0, 0);
        assertEquals(1, ups.stream().filter(u -> u.calibrationOutcome() != null).count());
        assertNull(m.baseline().learnedAxes());
        assertEquals(3, m.baseline().version());
        assertEquals(HeadAxisConvention.DEFAULT, m.effectiveAxes());
    }

    @Test
    void cancelAndClearLearnedAxes() {
        Mount mount = new Mount(0, 0, 20);
        PostureMonitor m = calibrated(mount);
        m.beginAxisCalibration();
        hold(m, mount, 10.04, 11.0, 0, 0);
        m.cancelAxisCalibration();
        assertEquals(Kind.NEUTRAL, m.process(mount.sample(11.0, 0, 0, 0)).state().kind());
        assertEquals(List.of(), axisOutcomes(feed(m, mount, 11.04, 20.0, rel -> new double[] {nod(rel, 20.0), 0.0})));

        m.beginAxisCalibration();
        feed(m, mount, 20.0, 26.0, rel -> new double[] {nod(rel - 0.5, 20.0), 0.0});
        assertEquals(2, m.baseline().version());
        m.clearLearnedAxes();
        assertNull(m.baseline().learnedAxes());
        assertEquals(HeadAxisConvention.DEFAULT, m.effectiveAxes());
        assertEquals(2, m.baseline().version());
    }

    @Test
    void neutralAndAxisCalibrationCancelEachOther() {
        PostureMonitor m = calibrated(Mount.NONE);
        m.beginAxisCalibration();
        hold(m, Mount.NONE, 10.04, 11.0, 0, 0);
        m.beginCalibration();
        List<PostureUpdate> ups = hold(m, Mount.NONE, 11.0, 22.0, 0, 0);
        assertEquals(List.of(), axisOutcomes(ups));
        assertEquals(1, ups.stream().filter(u -> u.calibrationOutcome() != null).count());

        m.beginCalibration();
        hold(m, Mount.NONE, 22.0, 23.0, 0, 0);
        m.beginAxisCalibration();
        List<PostureUpdate> axis = feed(m, Mount.NONE, 23.0, 30.0, rel -> new double[] {nod(rel - 0.5, 20.0), 0.0});
        assertEquals(0, axis.stream().filter(u -> u.calibrationOutcome() != null).count());
        assertEquals(1, axisOutcomes(axis).size());
        assertEquals(3, m.baseline().version());  // neutral (2), axis (3); the cancelled neutral one adds nothing
    }

    @Test
    void storedBaselineWithLearnedAxesIsUsedForTilt() {
        HeadAxisConvention learned = Pose.trueDeviceAxes(0, 0, 30, null);
        NeutralBaseline b = new NeutralBaseline(DOWN, 0.0, 250, 4, learned);
        PostureMonitor m = new PostureMonitor(PostureConfiguration.DEFAULT, b);
        assertEquals(learned, m.effectiveAxes());
        Mount mount = new Mount(0, 0, 30);
        List<PostureUpdate> ups = hold(m, mount, 0.0, 4.0, 0.0, 20.0);
        assertApprox(20.0, ups.get(ups.size() - 1).tilt().lateralDegrees(), 1e-3);
        assertApprox(0.0, ups.get(ups.size() - 1).tilt().forwardDegrees(), 1e-3);
    }
}
