package com.bachnguyennn.align.reference;

import static com.bachnguyennn.align.reference.Approx.assertApprox;
import static com.bachnguyennn.align.reference.Pose.poseSample;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.bachnguyennn.align.reference.Geometry.Vec3;
import com.bachnguyennn.align.reference.PostureState.Kind;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import org.junit.jupiter.api.Test;

/** Port of tests/test_monitor.py. */
class MonitorTest {

    private static final double RATE = 25.0;
    private static final double DT = 1.0 / RATE;

    private static NeutralBaseline baseline(int version) {
        return new NeutralBaseline(new Vec3(0.0, 0.0, -1.0), 0.0, 250, version);
    }

    private static NeutralBaseline baseline() {
        return baseline(1);
    }

    /** Feeds samples for start ≤ t < end; returns the updates. */
    private static List<PostureUpdate> feed(PostureMonitor m, double start, double end, double forward,
                                            double lateral, double rate) {
        List<PostureUpdate> out = new ArrayList<>();
        for (int i = 0; ; i++) {
            double t = PythonFormat.round(start + i / rate, 6);
            if (t >= end - 1e-9) {
                break;
            }
            out.add(m.process(poseSample(t, forward, lateral)));
        }
        return out;
    }

    private static List<PostureUpdate> feed(PostureMonitor m, double start, double end, double forward) {
        return feed(m, start, end, forward, 0.0, RATE);
    }

    private static List<PostureUpdate> feed(PostureMonitor m, double start, double end) {
        return feed(m, start, end, 0.0, 0.0, RATE);
    }

    private static PostureMonitor calibratedMonitor() {
        PostureMonitor m = new PostureMonitor(PostureConfiguration.DEFAULT);
        m.beginCalibration();
        feed(m, 0.0, 10.0 + DT);
        assertNotNull(m.baseline());
        return m;
    }

    private static List<ReminderDecision> reminders(List<PostureUpdate> updates) {
        return updates.stream().map(PostureUpdate::reminder).filter(Objects::nonNull).toList();
    }

    @Test
    void initialStates() {
        PostureMonitor m = new PostureMonitor();
        assertEquals(Kind.UNAVAILABLE, m.state().kind());
        PostureUpdate u = m.process(poseSample(0.0));
        assertEquals(Kind.NEEDS_CALIBRATION, u.state().kind());
        assertNull(u.tilt());
        PostureMonitor m2 = new PostureMonitor(PostureConfiguration.DEFAULT, baseline());
        assertEquals(Kind.NEUTRAL, m2.process(poseSample(0.0)).state().kind());
    }

    @Test
    void calibrationProgressSingleOutcomeAndVersion() {
        PostureMonitor m = new PostureMonitor();
        m.beginCalibration();
        assertEquals(Kind.CALIBRATING, m.state().kind());
        assertEquals(0.0, m.state().progress());
        List<PostureUpdate> ups = feed(m, 0.0, 12.0);
        List<PostureUpdate> outcomes = ups.stream().filter(u -> u.calibrationOutcome() != null).toList();
        assertEquals(1, outcomes.size());
        assertApprox(10.0, outcomes.get(0).timestamp());
        assertTrue(outcomes.get(0).calibrationOutcome().succeeded());
        assertEquals(Kind.CALIBRATING, ups.get(125).state().kind());
        assertApprox(0.5, ups.get(125).state().progress());
        assertEquals(Kind.NEUTRAL, outcomes.get(0).state().kind());
        assertEquals(1, m.baseline().version());
        assertEquals(251, m.baseline().sampleCount());
        m.beginCalibration();
        feed(m, 12.0, 23.0);
        assertEquals(2, m.baseline().version());
    }

    @Test
    void versionContinuesFromStoredBaseline() {
        PostureMonitor m = new PostureMonitor(PostureConfiguration.DEFAULT, baseline(5));
        m.beginCalibration();
        feed(m, 0.0, 10.5);
        assertEquals(6, m.baseline().version());
    }

    @Test
    void sustainedForwardTiltRemindsOnceAndClosesEpisode() {
        PostureMonitor m = calibratedMonitor();
        List<PostureUpdate> ups = new ArrayList<>(feed(m, 10.04, 20.0));
        ups.addAll(feed(m, 20.0, 80.0, 25.0));
        ups.addAll(feed(m, 80.0, 85.0));
        List<ReminderDecision> reminders = reminders(ups);
        assertEquals(1, reminders.size());
        ReminderDecision r = reminders.get(0);
        assertEquals(TiltDirection.FORWARD, r.direction());
        assertApprox(30.0, r.sustainedSeconds(), 0.05);
        assertApprox(25.0, r.deviationDegrees(), 0.1);
        // A 0 -> 25 deg step through the tau = 0.5 s filter crosses 15 deg after tau * ln(25 / 10).
        double lag = 0.5 * Math.log(25.0 / 10.0);
        assertApprox(50.0 + lag, r.timestamp(), DT);
        List<PostureEpisode> episodes = ups.stream().map(PostureUpdate::completedEpisode)
                .filter(Objects::nonNull).toList();
        assertEquals(1, episodes.size());
        assertTrue(episodes.get(0).reminderTriggered());
        assertApprox(80.0, episodes.get(0).endTimestamp(), 0.5);
        assertEquals(Kind.NEUTRAL, m.state().kind());
    }

    @Test
    void stateSinceIsDeviationOnset() {
        PostureMonitor m = calibratedMonitor();
        feed(m, 10.04, 12.0);
        feed(m, 12.0, 50.0, 25.0);
        PostureState s = m.state();
        assertEquals(Kind.SUSTAINED_TILT, s.kind());
        assertApprox(12.0 + 0.5 * Math.log(2.5), s.since(), DT);
    }

    @Test
    void cooldownBlocksSecondEpisodeAndResetCooldownAllowsIt() {
        PostureMonitor m = calibratedMonitor();
        feed(m, 10.04, 12.0);
        List<PostureUpdate> first = feed(m, 12.0, 50.0, 25.0);
        feed(m, 50.0, 55.0);
        List<PostureUpdate> second = feed(m, 55.0, 90.0, 25.0);
        assertEquals(1, reminders(first).size());
        assertEquals(0, reminders(second).size());
        feed(m, 90.0, 95.0);
        m.resetCooldown();
        List<PostureUpdate> third = feed(m, 95.0, 130.0, 25.0);
        assertEquals(1, reminders(third).size());
    }

    @Test
    void tiltSustainedDuringCooldownRemindsWhenCooldownEnds() {
        PostureMonitor m = calibratedMonitor();
        feed(m, 10.04, 12.0);
        List<PostureUpdate> first = feed(m, 12.0, 50.0, 25.0);
        feed(m, 50.0, 55.0);
        List<PostureUpdate> second = feed(m, 55.0, 400.0, 25.0);
        double firstTime = reminders(first).get(0).timestamp();
        List<ReminderDecision> deferred = reminders(second);
        assertEquals(1, deferred.size());
        assertApprox(firstTime + 300.0, deferred.get(0).timestamp(), 1.0 / 25.0);
    }

    @Test
    void interruptClosesEpisodeAndResets() {
        PostureMonitor m = calibratedMonitor();
        feed(m, 10.04, 12.0);
        feed(m, 12.0, 45.0, 25.0);
        PostureUpdate u = m.interrupt(45.5);
        assertNotNull(u.completedEpisode());
        assertEquals(45.5, u.completedEpisode().endTimestamp());
        assertEquals(Kind.UNAVAILABLE, u.state().kind());
        assertNull(u.tilt());
        // After reconnecting, deviation timers restart.
        u = m.process(poseSample(50.0, 25.0));
        assertEquals(Kind.DEVIATING, u.state().kind());
        assertEquals(50.0, u.state().since());
    }

    @Test
    void interruptFailsCalibration() {
        PostureMonitor m = new PostureMonitor();
        m.beginCalibration();
        feed(m, 0.0, 5.0);
        PostureUpdate u = m.interrupt(5.0);
        assertEquals(CalibrationFailure.SENSOR_INTERRUPTED, u.calibrationOutcome().failure());
        assertEquals(Kind.UNAVAILABLE, m.state().kind());
        assertEquals(Kind.NEEDS_CALIBRATION, m.process(poseSample(6.0)).state().kind());
    }

    @Test
    void gapActsLikeInterruptAtPreviousTimestamp() {
        PostureMonitor m = calibratedMonitor();
        feed(m, 10.04, 12.0);
        feed(m, 12.0, 45.0, 25.0);
        double last = 45.0 - DT;
        PostureUpdate u = m.process(poseSample(47.0, 25.0));
        assertNotNull(u.completedEpisode());
        assertApprox(last, u.completedEpisode().endTimestamp());
        assertEquals(Kind.DEVIATING, u.state().kind());
        assertEquals(47.0, u.state().since());
    }

    @Test
    void gapDuringCalibrationReportsSensorInterruptedOnNextSample() {
        PostureMonitor m = new PostureMonitor();
        m.beginCalibration();
        feed(m, 0.0, 4.0);
        PostureUpdate u = m.process(poseSample(6.0));
        assertNotNull(u.calibrationOutcome());
        assertEquals(CalibrationFailure.SENSOR_INTERRUPTED, u.calibrationOutcome().failure());
        assertEquals(Kind.NEEDS_CALIBRATION, u.state().kind());
    }

    @Test
    void decimationCapsProcessingRate() {
        PostureConfiguration cfg = PostureConfiguration.builder().maxProcessingRateHz(10.0).build();
        PostureMonitor m = new PostureMonitor(cfg, baseline());
        int processed = 0;
        for (int i = 0; i < 250; i++) {  // 10 s at 25 Hz
            Double before = m.lastProcessedTimestamp();
            m.process(poseSample(PythonFormat.round(i * DT, 6)));
            if (!Objects.equals(m.lastProcessedTimestamp(), before)) {
                processed++;
            }
        }
        assertApprox(100, processed, 1);
    }

    @Test
    void configurationChangeAppliesFromNextSample() {
        PostureMonitor m = calibratedMonitor();
        feed(m, 10.04, 12.0);
        feed(m, 12.0, 14.0, 12.0);
        assertEquals(Kind.NEUTRAL, m.state().kind());
        m.setConfiguration(m.configuration().replacing(b -> b.forwardThresholdDegrees(10.0)));
        PostureUpdate u = m.process(poseSample(14.0, 12.0));
        assertEquals(Kind.DEVIATING, u.state().kind());
    }

    @Test
    void missingGravityIsDerivedFromAttitude() {
        PostureMonitor m = new PostureMonitor(PostureConfiguration.DEFAULT, baseline());
        m.process(poseSample(0.0, 0.0));
        PostureUpdate u = null;
        for (int i = 1; i < 100; i++) {
            u = m.process(poseSample(i * DT, 20.0, 0.0, false));
        }
        assertApprox(20.0, u.tilt().forwardDegrees(), 0.01);
    }

    @Test
    void nonIncreasingAndZeroGravitySamplesAreIgnored() {
        PostureMonitor m = new PostureMonitor(PostureConfiguration.DEFAULT, baseline());
        m.process(poseSample(1.0));
        Double before = m.lastProcessedTimestamp();
        m.process(poseSample(1.0, 30.0));
        m.process(poseSample(0.5, 30.0));
        m.process(new MotionSample(2.0, poseSample(0).attitude(), new Vec3(0, 0, 0)));
        assertEquals(before, m.lastProcessedTimestamp());
    }

    @Test
    void beginCalibrationDuringSustainedTiltDeliversEpisodeOnNextUpdate() {
        PostureMonitor m = calibratedMonitor();
        feed(m, 10.04, 12.0);
        feed(m, 12.0, 45.0, 25.0);
        Double last = m.lastProcessedTimestamp();
        m.beginCalibration();
        assertEquals(Kind.CALIBRATING, m.state().kind());
        PostureUpdate u = m.process(poseSample(45.0, 0.0));
        assertNotNull(u.completedEpisode());
        assertEquals(last, u.completedEpisode().endTimestamp());
    }

    @Test
    void cancelCalibrationKeepsPreviousBaseline() {
        PostureMonitor m = calibratedMonitor();
        NeutralBaseline b = m.baseline();
        m.beginCalibration();
        feed(m, 10.04, 13.0);
        m.cancelCalibration();
        PostureUpdate u = m.process(poseSample(13.0));
        assertEquals(b, m.baseline());
        assertEquals(Kind.NEUTRAL, u.state().kind());
        assertNull(u.calibrationOutcome());
    }
}
