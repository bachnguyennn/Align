package com.bachnguyennn.align.reference;

import static com.bachnguyennn.align.reference.Approx.assertApprox;
import static com.bachnguyennn.align.reference.Geometry.angleBetweenDegrees;
import static com.bachnguyennn.align.reference.Geometry.gravityInHeadFrame;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.bachnguyennn.align.reference.CalibrationService.CalibrationStep;
import com.bachnguyennn.align.reference.Geometry.Vec3;
import com.bachnguyennn.align.reference.PostureState.Kind;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.util.List;
import org.junit.jupiter.api.Test;

/**
 * D-022: the "get ready" countdown before a neutral calibration. Mirrored by
 * CalibrationCountdownTests (Swift) and pipeline.test.js (JavaScript).
 */
class CalibrationCountdownTest {

    private static final PostureConfiguration CFG = PostureConfiguration.DEFAULT;

    private static Vec3 gFor(double forward) {
        return gravityInHeadFrame(Pose.poseAttitude(forward, 0.0));
    }

    /** Looking down at the phone (30 deg) before {@code lookUpAt}, neutral afterwards. */
    private static Vec3 lookUp(double t, double lookUpAt) {
        return gFor(t < lookUpAt ? 30.0 : 0.0);
    }

    private static MotionSample sample(double t, double forward) {
        return new MotionSample(t, Pose.poseAttitude(forward, 0.0), gFor(forward));
    }

    @Test
    void defaultCountdownIsThreeSeconds() {
        assertEquals(3.0, CFG.calibrationCountdown());
        assertEquals(0.0, PostureConfiguration.fromOverrides(
                Json.parse("{\"calibrationCountdown\": 0}")).calibrationCountdown());
    }

    @Test
    void countdownSamplesAreDiscardedAndTheHoldStartsAfterIt() {
        CalibrationService c = new CalibrationService();
        c.begin();
        assertTrue(c.isCountingDown());
        assertEquals(3.0, c.countdownRemaining(3.0));  // before the first sample
        CalibrationStep step = null;
        int i = 0;
        for (; i <= 13 * 25; i++) {
            double t = i / 25.0;
            step = c.add(lookUp(t, 2.0), t, CFG);
            if (t < 3.0 - 1e-9) {
                assertFalse(step.finished());
                assertEquals(0.0, step.progress());
                assertTrue(c.isCountingDown());
                assertApprox(3.0 - t, c.countdownRemaining(3.0), 1e-9);
            } else {
                assertFalse(c.isCountingDown() && c.isActive(), "hold started at t = " + t);
                assertEquals(0.0, c.countdownRemaining(3.0));
            }
            if (step.finished()) {
                break;
            }
        }
        assertTrue(step.finished());
        assertApprox(13.0, i / 25.0, 1e-9);           // 3 s countdown + 10 s hold
        assertNull(step.failure());
        assertEquals(251, step.sampleCount());        // t = 3.0 .. 13.0 inclusive; the 75 countdown samples are dropped
        assertApprox(0.0, angleBetweenDegrees(step.meanGravity(), gFor(0.0)), 1e-9);
    }

    @Test
    void withoutTheCountdownLookingUpFailsTheCalibration() {
        CalibrationService c = new CalibrationService();
        c.begin();
        CalibrationStep step = null;
        for (int i = 0; i <= 10 * 25 && (step == null || !step.finished()); i++) {
            double t = i / 25.0;
            step = c.add(lookUp(t, 2.0), t, TestConfigs.NO_COUNTDOWN);
        }
        assertEquals(CalibrationFailure.TOO_MUCH_MOVEMENT, step.failure());
    }

    @Test
    void movementDuringTheHoldStillFails() {
        CalibrationService c = new CalibrationService();
        c.begin();
        CalibrationStep step = null;
        for (int i = 0; i <= 13 * 25 && (step == null || !step.finished()); i++) {
            double t = i / 25.0;
            // Neutral during the countdown, then a 9 deg nod for the first half of the hold.
            step = c.add(gFor(t >= 3.0 && t < 8.0 ? 9.0 : 0.0), t, CFG);
        }
        assertEquals(CalibrationFailure.TOO_MUCH_MOVEMENT, step.failure());
    }

    @Test
    void monitorReportsCalibratingAtZeroAndTheRemainingCountdown() {
        PostureMonitor m = new PostureMonitor(CFG);
        m.process(sample(0.0, 30.0));
        assertNull(m.calibrationCountdownRemaining());  // not calibrating
        m.beginCalibration();
        assertEquals(3.0, m.calibrationCountdownRemaining());
        PostureUpdate u = m.process(sample(0.04, 30.0));
        assertEquals(PostureState.calibrating(0.0), u.state());
        assertApprox(3.0, m.calibrationCountdownRemaining(), 1e-9);  // the countdown starts on this sample
        for (int i = 2; i <= 50; i++) {
            u = m.process(sample(i * 0.04, 30.0));
        }
        assertEquals(PostureState.calibrating(0.0), u.state());
        assertApprox(3.0 - (2.0 - 0.04), m.calibrationCountdownRemaining(), 1e-9);
        for (int i = 51; i <= 100; i++) {
            u = m.process(sample(i * 0.04, 0.0));
        }
        assertNull(m.calibrationCountdownRemaining());  // hold started at t = 3.04
        assertEquals(Kind.CALIBRATING, u.state().kind());
        assertTrue(u.state().progress() > 0.0);
    }

    @Test
    void cancelDuringTheCountdownStopsWithoutAnOutcome() {
        PostureMonitor m = new PostureMonitor(CFG);
        m.beginCalibration();
        for (int i = 0; i < 25; i++) {
            assertNull(m.process(sample(i * 0.04, 30.0)).calibrationOutcome());
        }
        m.cancelCalibration();
        assertNull(m.calibrationCountdownRemaining());
        PostureUpdate u = m.process(sample(1.0, 0.0));
        assertEquals(Kind.NEEDS_CALIBRATION, u.state().kind());
        assertNull(u.calibrationOutcome());
    }

    @Test
    void lookUpFixtureNeedsTheCountdown() {
        ObjectNode fx = Fixtures.loadFixture(Fixtures.fixtureDir().resolve("calibration_countdown_look_up.json"));
        assertEquals(List.of("succeeded"), Fixtures.replay(fx).calibrationOutcomes());
        PostureConfiguration withoutCountdown = PostureConfiguration.fromOverrides(fx.get("config"))
                .replacing(b -> b.calibrationCountdown(0.0));
        assertEquals(List.of("tooMuchMovement"), Fixtures.replay(fx, withoutCountdown).calibrationOutcomes());
    }
}
