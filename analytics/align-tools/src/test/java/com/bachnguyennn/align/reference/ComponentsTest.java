package com.bachnguyennn.align.reference;

import static com.bachnguyennn.align.reference.Approx.assertApprox;
import static com.bachnguyennn.align.reference.Geometry.angleBetweenDegrees;
import static com.bachnguyennn.align.reference.Geometry.gravityInHeadFrame;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.bachnguyennn.align.reference.CalibrationService.CalibrationStep;
import com.bachnguyennn.align.reference.Geometry.Vec3;
import com.bachnguyennn.align.reference.PostureDetector.DetectorOutput;
import com.bachnguyennn.align.reference.PostureState.Kind;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;

/** Port of tests/test_components.py: MotionFilter, CalibrationService, PostureDetector, ReminderDecisionEngine. */
class ComponentsTest {

    private static final PostureConfiguration CFG = PostureConfiguration.DEFAULT;

    private static Vec3 gFor(double forward, double lateral) {
        return gravityInHeadFrame(Pose.poseAttitude(forward, lateral));
    }

    private static Vec3 gFor(double forward) {
        return gFor(forward, 0.0);
    }

    private static TiltEstimate tilt(double t, double forward, double lateral) {
        return new TiltEstimate(t, forward, lateral, Math.hypot(forward, lateral));
    }

    private static TiltEstimate tilt(double t, double forward) {
        return tilt(t, forward, 0.0);
    }

    // MARK: MotionFilter

    @Test
    void filterFirstSamplePassesThroughAndStepReaches63PercentAtTau() {
        MotionFilter f = new MotionFilter();
        Vec3 g0 = gFor(0);
        Vec3 g1 = gFor(10);
        assertEquals(g0, f.update(g0, 0.0, 0.5));
        Vec3 out = null;
        for (int i = 1; i <= 500; i++) {  // 1 kHz for 0.5 s
            out = f.update(g1, i * 0.001, 0.5);
        }
        double angle = angleBetweenDegrees(g0, out);
        assertApprox(10 * (1 - Math.exp(-1)), angle, 0.05);
    }

    @Test
    void filterResponseIsSampleRateIndependent() {
        Vec3 g0 = gFor(0);
        Vec3 g1 = gFor(10);
        List<Double> results = new ArrayList<>();
        for (double rate : new double[] {25.0, 100.0}) {
            MotionFilter f = new MotionFilter();
            f.update(g0, 0.0, 0.5);
            int n = (int) (rate * 1.0);
            Vec3 out = null;
            for (int i = 1; i <= n; i++) {
                out = f.update(g1, i / rate, 0.5);
            }
            results.add(angleBetweenDegrees(g0, out));
        }
        assertApprox(results.get(1), results.get(0), 0.02);
    }

    @Test
    void filterZeroTimeConstantAndReset() {
        MotionFilter f = new MotionFilter();
        f.update(gFor(0), 0.0, 0.0);
        Vec3 g1 = gFor(12);
        assertApprox(g1, f.update(g1, 0.04, 0.0));
        f.reset();
        assertNull(f.value());
    }

    // MARK: CalibrationService

    private record CalibrationRun(CalibrationStep step, int used) {}

    private static CalibrationRun runCalibration(List<Vec3> gravities, double rate) {
        CalibrationService c = new CalibrationService();
        c.begin();
        CalibrationStep step = null;
        for (int i = 0; i < gravities.size(); i++) {
            step = c.add(gravities.get(i), i / rate, CFG);
            if (step.finished()) {
                return new CalibrationRun(step, i + 1);
            }
        }
        return new CalibrationRun(step, gravities.size());
    }

    @Test
    void calibrationSucceedsWithMeanGravityAfterDuration() {
        List<Vec3> gs = new ArrayList<>();
        for (int i = 0; i < 400; i++) {
            gs.add(gFor(2 * Math.sin(i * 0.3), 1.0));
        }
        CalibrationRun run = runCalibration(gs, 25.0);
        assertTrue(run.step().finished());
        assertNull(run.step().failure());
        assertEquals(251, run.used());  // samples at t = 0 .. 10.0 inclusive at 25 Hz
        assertEquals(251, run.step().sampleCount());
        assertTrue(angleBetweenDegrees(run.step().meanGravity(), gFor(0, 1.0)) < 0.2);
    }

    @Test
    void calibrationReportsProgress() {
        CalibrationService c = new CalibrationService();
        c.begin();
        c.add(gFor(0), 0.0, CFG);
        CalibrationStep s = c.add(gFor(0), 5.0, CFG);
        assertFalse(s.finished());
        assertApprox(0.5, s.progress());
    }

    @Test
    void calibrationFailsWithTooMuchMovement() {
        List<Vec3> gs = new ArrayList<>();
        for (int i = 0; i < 400; i++) {
            gs.add(gFor(8 * Math.sin(i * 0.1)));
        }
        assertEquals(CalibrationFailure.TOO_MUCH_MOVEMENT, runCalibration(gs, 25.0).step().failure());
    }

    @Test
    void calibrationFailsWithInsufficientSamples() {
        List<Vec3> gs = new ArrayList<>();
        for (int i = 0; i < 100; i++) {
            gs.add(gFor(0));
        }
        CalibrationRun run = runCalibration(gs, 5.0);  // 10 s at 5 Hz = 51 samples
        assertEquals(CalibrationFailure.INSUFFICIENT_SAMPLES, run.step().failure());
        assertEquals(51, run.used());
    }

    /** 251 samples (10 s at 25 Hz) at neutral, with {@code fidget} samples at 10 deg forward from index 100. */
    private static List<Vec3> fidgetGravities(int fidget) {
        List<Vec3> gs = new ArrayList<>();
        for (int i = 0; i < 251; i++) {
            gs.add(i >= 100 && i < 100 + fidget ? gFor(10.0) : gFor(0.0, 0.5));
        }
        return gs;
    }

    private static CalibrationStep runCalibration(List<Vec3> gravities, PostureConfiguration config) {
        CalibrationService c = new CalibrationService();
        c.begin();
        CalibrationStep step = null;
        for (int i = 0; i < gravities.size(); i++) {
            step = c.add(gravities.get(i), i / 25.0, config);
            if (step.finished()) {
                break;
            }
        }
        return step;
    }

    /** D-017 (b): a brief fidget fails the v1 rule (quantile 1.0) but passes 0.9, without biasing the baseline. */
    @Test
    void calibrationQuantileToleratesABriefFidgetAndUsesTheInlierMean() {
        List<Vec3> gs = fidgetGravities(20);  // 0.8 s = 8 % of the samples
        PostureConfiguration v1 = CFG.replacing(b -> b.calibrationSpreadQuantile(1.0));
        assertEquals(CalibrationFailure.TOO_MUCH_MOVEMENT, runCalibration(gs, v1).failure());
        CalibrationStep step = runCalibration(gs, CFG);
        assertNull(step.failure());
        assertApprox(0.0, angleBetweenDegrees(step.meanGravity(), gFor(0.0, 0.5)), 1e-9);
        // 30 samples (12 %) are too many for 0.9.
        assertEquals(CalibrationFailure.TOO_MUCH_MOVEMENT, runCalibration(fidgetGravities(30), CFG).failure());
    }

    /** With every sample within the spread the baseline is bit for bit the v1 mean. */
    @Test
    void calibrationWithoutOutliersIsIdenticalToV1() {
        List<Vec3> gs = new ArrayList<>();
        for (int i = 0; i < 300; i++) {
            gs.add(gFor(2 * Math.sin(i * 0.3), 1.0));
        }
        CalibrationStep q09 = runCalibration(gs, CFG);
        CalibrationStep q10 = runCalibration(gs, CFG.replacing(b -> b.calibrationSpreadQuantile(1.0)));
        assertEquals(q10.meanGravity(), q09.meanGravity());
    }

    /** 251 samples (10 s at 25 Hz) of a steady slouch from 0 to {@code degrees} forward. */
    private static List<Vec3> slouchGravities(double degrees) {
        List<Vec3> gs = new ArrayList<>();
        for (int i = 0; i < 251; i++) {
            gs.add(gFor(degrees * i / 250.0, 0.5));
        }
        return gs;
    }

    /** D-020: a steady 10 deg slouch passes the spread rule but fails the drift rule. */
    @Test
    void calibrationDriftRejectsASlowSlouch() {
        PostureConfiguration noDrift = CFG.replacing(b -> b.calibrationMaxDriftDegrees(180.0));
        assertNull(runCalibration(slouchGravities(10.0), noDrift).failure());
        assertEquals(CalibrationFailure.TOO_MUCH_MOVEMENT, runCalibration(slouchGravities(10.0), CFG).failure());
        // 3 deg over 10 s: first and last 2 s means are 2.4 deg apart, under the 3 deg limit.
        assertNull(runCalibration(slouchGravities(3.0), CFG).failure());
        assertEquals(CalibrationFailure.TOO_MUCH_MOVEMENT, runCalibration(slouchGravities(4.0), CFG).failure());
    }

    /** 251 samples at neutral with a 1 s (25-sample) fidget to 10 deg forward starting at {@code start}. */
    private static List<Vec3> fidgetAt(int start) {
        List<Vec3> gs = new ArrayList<>();
        for (int i = 0; i < 251; i++) {
            gs.add(i >= start && i < start + 25 ? gFor(10.0) : gFor(0.0, 0.5));
        }
        return gs;
    }

    /** D-020: the drift window means use spread-rule inliers, so a fidget at either end is not drift. */
    @Test
    void driftIgnoresABriefFidgetInTheFirstOrLastWindow() {
        for (int start : new int[] {0, 226}) {  // first 1 s, last 1 s (t = 9.04 .. 10.0)
            CalibrationStep step = runCalibration(fidgetAt(start), CFG);
            assertNull(step.failure(), "fidget at sample " + start);
            assertApprox(0.0, angleBetweenDegrees(step.meanGravity(), gFor(0.0, 0.5)), 1e-9);
            // Counting every sample, the fidget would shift its window's mean by ~5 deg.
            List<Double> ts = new ArrayList<>();
            for (int i = 0; i < 251; i++) {
                ts.add(i / 25.0);
            }
            assertTrue(CalibrationService.driftDegrees(fidgetAt(start), ts, 2.0) > 3.0);
        }
    }

    @Test
    void driftWindowWithoutInliersFails() {
        // The first 6 samples (t ≤ 0.2 s, 2.4 % of them) are outliers: the spread rule passes but a
        // 0.2 s drift window has no inliers.
        List<Vec3> gs = new ArrayList<>();
        for (int i = 0; i < 251; i++) {
            gs.add(i < 6 ? gFor(15.0) : gFor(0.0, 0.5));
        }
        PostureConfiguration shortWindow = CFG.replacing(b -> b.calibrationDriftWindow(0.2));
        assertEquals(CalibrationFailure.TOO_MUCH_MOVEMENT, runCalibration(gs, shortWindow).failure());
        assertNull(runCalibration(gs, CFG).failure());  // the 2 s window still has inliers
        List<Boolean> none = new ArrayList<>();
        for (int i = 0; i < 3; i++) {
            none.add(false);
        }
        assertTrue(Double.isNaN(CalibrationService.driftDegrees(List.of(gFor(0), gFor(0), gFor(0)),
                List.of(0.0, 1.0, 2.0), none, 2.0)));
    }

    @Test
    void driftWindowsIncludeTheirEdgesAndUseTimestamps() {
        // Samples at t = 0, 1, 2, ..., 10 s: 0 deg up to t = 2 s, then 10 deg from t = 3 s.
        List<Vec3> gs = new ArrayList<>();
        List<Double> ts = new ArrayList<>();
        for (int i = 0; i <= 10; i++) {
            gs.add(gFor(i <= 2 ? 0.0 : 10.0));
            ts.add((double) i);
        }
        assertApprox(10.0, CalibrationService.driftDegrees(gs, ts, 2.0), 1e-9);  // first window t = 0..2 (edge included)
        assertApprox(7.5, CalibrationService.driftDegrees(gs, ts, 3.0), 0.05);  // mean of 0, 0, 0, 10 is ~2.5 deg
        assertApprox(0.0, CalibrationService.driftDegrees(List.of(gFor(5.0)), List.of(4.0), 2.0), 1e-12);
    }

    @Test
    void quantileComparisonToleratesRounding() {
        assertTrue(CalibrationService.hasEnoughInliers(225, 250, 0.9));
        assertFalse(CalibrationService.hasEnoughInliers(224, 250, 0.9));
        assertTrue(CalibrationService.hasEnoughInliers(250, 250, 1.0));
        assertFalse(CalibrationService.hasEnoughInliers(249, 250, 1.0));
        assertTrue(CalibrationService.hasEnoughInliers(0, 250, 0.0));
        assertFalse(CalibrationService.hasEnoughInliers(249, 250, 1.5));  // clamped to 1
    }

    // MARK: PostureDetector

    @Test
    void detectorNeutralDeviatingSustainedAndEpisode() {
        PostureDetector d = new PostureDetector();
        assertEquals(Kind.NEUTRAL, d.update(tilt(0, 10), CFG).state().kind());
        DetectorOutput out = d.update(tilt(1, 16), CFG);
        assertEquals(Kind.DEVIATING, out.state().kind());
        assertEquals(TiltDirection.FORWARD, out.state().direction());
        assertEquals(1.0, out.state().since());
        out = d.update(tilt(30.9, 16), CFG);
        assertEquals(Kind.DEVIATING, out.state().kind());
        out = d.update(tilt(31.0, 20), CFG);
        assertEquals(Kind.SUSTAINED_TILT, out.state().kind());
        assertTrue(out.becameSustained());
        assertFalse(d.update(tilt(32, 13), CFG).becameSustained());  // hysteresis: 13 >= 15 - 3
        out = d.update(tilt(40, 11.9), CFG);
        assertEquals(Kind.NEUTRAL, out.state().kind());
        PostureEpisode ep = out.completedEpisode();
        assertEquals(TiltDirection.FORWARD, ep.direction());
        assertEquals(1.0, ep.startTimestamp());
        assertEquals(40.0, ep.endTimestamp());
        assertEquals(20.0, ep.peakDeviationDegrees());
        assertFalse(ep.reminderTriggered());
    }

    @Test
    void shortDeviationProducesNoEpisode() {
        PostureDetector d = new PostureDetector();
        d.update(tilt(0, 20), CFG);
        DetectorOutput out = d.update(tilt(5, 0), CFG);
        assertEquals(Kind.NEUTRAL, out.state().kind());
        assertNull(out.completedEpisode());
    }

    static Stream<Arguments> precedenceCases() {
        return Stream.of(
                Arguments.of(16, 0, TiltDirection.FORWARD),
                Arguments.of(-21, 0, TiltDirection.BACKWARD),
                Arguments.of(0, 15, TiltDirection.RIGHT),
                Arguments.of(0, -15.5, TiltDirection.LEFT),
                Arguments.of(-21, 16, TiltDirection.RIGHT),   // backward 21/20 = 1.05 < right 16/15 = 1.067
                Arguments.of(18, -16, TiltDirection.FORWARD), // 1.2 vs 1.067
                Arguments.of(-19, 0, null),
                Arguments.of(14.9, 14.9, null));
    }

    @ParameterizedTest(name = "forward={0}, lateral={1} -> {2}")
    @MethodSource("precedenceCases")
    void directionPrecedenceByRatio(double forward, double lateral, TiltDirection expected) {
        assertEquals(expected, PostureDetector.dominantDirection(tilt(0, forward, lateral), CFG));
    }

    @Test
    void directionIsLockedDuringDeviationAndReleaseCanStartNewDirection() {
        PostureDetector d = new PostureDetector();
        d.update(tilt(0, 16, 0), CFG);
        DetectorOutput out = d.update(tilt(1, 16, 30), CFG);  // lateral now dominates, but forward stays engaged
        assertEquals(TiltDirection.FORWARD, out.state().direction());
        out = d.update(tilt(2, 5, 30), CFG);  // forward released; right over threshold
        assertEquals(Kind.DEVIATING, out.state().kind());
        assertEquals(TiltDirection.RIGHT, out.state().direction());
        assertEquals(2.0, out.state().since());
    }

    @Test
    void interruptClosesOnlySustained() {
        PostureDetector d = new PostureDetector();
        d.update(tilt(0, 20), CFG);
        assertNull(d.interrupt(3));
        d.update(tilt(10, 20), CFG);
        d.update(tilt(40, 20), CFG);
        PostureEpisode ep = d.interrupt(41);
        assertEquals(41.0, ep.endTimestamp());
        assertEquals(10.0, ep.startTimestamp());
        assertEquals(Kind.NEUTRAL, d.state().kind());
    }

    @Test
    void floatingPointDurationEdgeCountsAsElapsed() {
        PostureDetector d = new PostureDetector();
        assertTrue(32.05 - 2.05 < 30);  // 29.999999999999996 in IEEE doubles
        d.update(tilt(2.05, 20), CFG);
        DetectorOutput out = d.update(tilt(32.05, 20), CFG);
        assertTrue(out.becameSustained());
    }

    // MARK: ReminderDecisionEngine

    @Test
    void reminderCooldownAndReset() {
        ReminderDecisionEngine r = new ReminderDecisionEngine();
        assertNotNull(r.evaluate(100, TiltDirection.FORWARD, 20, 30, 300));
        assertNull(r.evaluate(399.9, TiltDirection.FORWARD, 20, 30, 300));
        assertNotNull(r.evaluate(400, TiltDirection.FORWARD, 20, 30, 300));
        assertNull(r.evaluate(401, TiltDirection.FORWARD, 20, 30, 300));
        r.reset();
        assertNotNull(r.evaluate(402, TiltDirection.FORWARD, 20, 30, 300));
    }

    @Test
    void reminderAllowedWhenClockGoesBackwards() {
        ReminderDecisionEngine r = new ReminderDecisionEngine();
        r.evaluate(1000, TiltDirection.FORWARD, 20, 30, 300);
        assertNotNull(r.evaluate(10, TiltDirection.LEFT, 20, 30, 300));
    }
}
