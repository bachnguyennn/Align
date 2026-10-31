package com.bachnguyennn.align.reference;

import static com.bachnguyennn.align.reference.Geometry.gravityInHeadFrame;
import static com.bachnguyennn.align.reference.Geometry.length;
import static com.bachnguyennn.align.reference.Geometry.normalized;

import com.bachnguyennn.align.reference.CalibrationService.CalibrationStep;
import com.bachnguyennn.align.reference.Geometry.Vec3;
import com.bachnguyennn.align.reference.PostureDetector.DetectorOutput;
import com.bachnguyennn.align.reference.PostureDetector.Phase;
import com.bachnguyennn.align.reference.PostureState.Kind;

/**
 * The full per-sample pipeline. Mirrors Swift {@code PostureMonitor}.
 *
 * <p>Per sample:
 * <ol>
 *   <li>Validate: gravity (or, if missing, gravity derived from the attitude) must be non-zero;
 *       timestamps must strictly increase. Invalid samples are ignored (passive update).</li>
 *   <li>Gap check: if the gap to the previous received sample exceeds {@code maxSampleGap}, act
 *       like {@code interrupt(at: previous timestamp)} and then process this sample from a fresh
 *       state.</li>
 *   <li>Decimation by {@code maxProcessingRateHz} (phase-accumulating schedule, so a 25 Hz stream
 *       capped at 10 Hz yields 10 Hz on average). Dropped samples give a passive update.</li>
 *   <li>Smoothing (MotionFilter), then calibration or tilt estimation + PostureDetector.</li>
 *   <li>ReminderDecisionEngine on every sustained update until the episode has reminded
 *       (D-016).</li>
 * </ol>
 */
public final class PostureMonitor {

    /** Decimation schedule tolerance (seconds). */
    public static final double DECIMATION_EPSILON = 1e-6;

    private PostureConfiguration configuration;
    private NeutralBaseline baseline;
    private final boolean orthogonalizeAxes;
    private final MotionFilter filter = new MotionFilter();
    private final CalibrationService calibration = new CalibrationService();
    private final PostureDetector detector = new PostureDetector();
    private final ReminderDecisionEngine reminders = new ReminderDecisionEngine();
    private Double lastReceivedTimestamp;
    private Double lastProcessedTimestamp;
    private Double nextProcessingDue;
    private boolean hasData = false;
    private TiltEstimate lastTilt;
    private PostureEpisode pendingEpisode;

    private record InterruptResult(PostureEpisode episode, CalibrationOutcome outcome) {}

    public PostureMonitor() {
        this(PostureConfiguration.DEFAULT, null, true);
    }

    public PostureMonitor(PostureConfiguration configuration) {
        this(configuration, null, true);
    }

    public PostureMonitor(PostureConfiguration configuration, NeutralBaseline baseline) {
        this(configuration, baseline, true);
    }

    public PostureMonitor(PostureConfiguration configuration, NeutralBaseline baseline, boolean orthogonalizeAxes) {
        this.configuration = configuration != null ? configuration : PostureConfiguration.DEFAULT;
        this.baseline = baseline;
        this.orthogonalizeAxes = orthogonalizeAxes;
    }

    // MARK: - Public API

    public PostureConfiguration configuration() {
        return configuration;
    }

    /** Applies from the next sample. */
    public void setConfiguration(PostureConfiguration configuration) {
        this.configuration = configuration;
    }

    public NeutralBaseline baseline() {
        return baseline;
    }

    public Double lastProcessedTimestamp() {
        return lastProcessedTimestamp;
    }

    public PostureState state() {
        if (calibration.isActive()) {
            return PostureState.calibrating(calibration.progress(configuration.calibrationDuration()));
        }
        if (!hasData) {
            return PostureState.of(Kind.UNAVAILABLE);
        }
        if (baseline == null) {
            return PostureState.of(Kind.NEEDS_CALIBRATION);
        }
        return detector.state();
    }

    /**
     * Starts collecting a new baseline. An open sustained episode is closed at the last processed
     * timestamp and delivered with the next update.
     */
    public void beginCalibration() {
        if (detector.phase() != Phase.NEUTRAL) {
            double end = lastProcessedTimestamp != null ? lastProcessedTimestamp : 0.0;
            PostureEpisode episode = detector.interrupt(end);
            if (episode != null && pendingEpisode == null) {
                pendingEpisode = episode;
            }
        }
        detector.reset();
        calibration.begin();
    }

    public void cancelCalibration() {
        calibration.cancel();
        detector.reset();
    }

    public void resetCooldown() {
        reminders.reset();
    }

    public PostureUpdate interrupt(double at) {
        InterruptResult result = interruptCore(at);
        return new PostureUpdate(at, state(), null, null, result.episode(), result.outcome());
    }

    public PostureUpdate process(MotionSample sample) {
        double t = sample.timestamp();
        Vec3 raw = sample.gravity() != null ? sample.gravity() : gravityInHeadFrame(sample.attitude());
        Vec3 gravity = normalized(raw);
        if (length(gravity) == 0.0) {
            return passiveUpdate(t, null, null);
        }
        if (lastReceivedTimestamp != null && t <= lastReceivedTimestamp) {
            return passiveUpdate(t, null, null);
        }

        PostureEpisode gapEpisode = null;
        CalibrationOutcome gapOutcome = null;
        if (lastReceivedTimestamp != null && t - lastReceivedTimestamp > configuration.maxSampleGap()) {
            InterruptResult result = interruptCore(lastReceivedTimestamp);
            gapEpisode = result.episode();
            gapOutcome = result.outcome();
        }
        lastReceivedTimestamp = t;

        if (!shouldProcess(t)) {
            return passiveUpdate(t, gapEpisode, gapOutcome);
        }

        PostureConfiguration config = configuration;
        Vec3 smoothed = filter.update(gravity, t, config.smoothingTimeConstant());
        hasData = true;
        lastProcessedTimestamp = t;

        PostureEpisode episode = takePendingEpisode();
        if (episode == null) {
            episode = gapEpisode;
        }
        CalibrationOutcome outcome = gapOutcome;
        ReminderDecision reminder = null;
        TiltEstimate tilt = null;

        if (calibration.isActive()) {
            CalibrationStep step = calibration.add(smoothed, t, config);
            if (step.finished()) {
                if (step.failure() == null) {
                    int previousVersion = baseline != null ? baseline.version() : 0;
                    baseline = new NeutralBaseline(step.meanGravity(), t, step.sampleCount(), previousVersion + 1);
                    outcome = CalibrationOutcome.success(baseline);
                } else {
                    outcome = CalibrationOutcome.failed(step.failure());
                }
                detector.reset();
            }
            if (baseline != null) {
                tilt = estimate(t, smoothed);
            }
        } else if (baseline != null) {
            tilt = estimate(t, smoothed);
            DetectorOutput out = detector.update(tilt, config);
            if (out.completedEpisode() != null && episode == null) {
                episode = out.completedEpisode();
            }
            // Evaluated on every sustained update until this episode has reminded, so a tilt that
            // became sustained during the cooldown still reminds once the cooldown ends (D-016).
            if (detector.phase() == Phase.SUSTAINED && !detector.reminderTriggered()) {
                TiltDirection direction = detector.direction();
                ReminderDecision decision = reminders.evaluate(
                        t,
                        direction,
                        PostureDetector.componentDegrees(tilt, direction),
                        t - detector.since(),
                        config.reminderCooldown());
                if (decision != null) {
                    detector.markReminderTriggered();
                    reminder = decision;
                }
            }
        }

        lastTilt = tilt;
        return new PostureUpdate(t, state(), tilt, reminder, episode, outcome);
    }

    // MARK: - Internals

    private TiltEstimate estimate(double t, Vec3 smoothed) {
        return Tilt.estimateTilt(t, smoothed, baseline.gravity(), configuration.axes(), orthogonalizeAxes);
    }

    private PostureEpisode takePendingEpisode() {
        PostureEpisode episode = pendingEpisode;
        pendingEpisode = null;
        return episode;
    }

    private InterruptResult interruptCore(double at) {
        PostureEpisode episode = takePendingEpisode();
        PostureEpisode detectorEpisode = detector.interrupt(at);
        if (episode == null) {
            episode = detectorEpisode;
        }
        CalibrationOutcome outcome = null;
        if (calibration.isActive()) {
            calibration.cancel();
            outcome = CalibrationOutcome.failed(CalibrationFailure.SENSOR_INTERRUPTED);
        }
        filter.reset();
        hasData = false;
        lastReceivedTimestamp = null;
        lastProcessedTimestamp = null;
        nextProcessingDue = null;
        lastTilt = null;
        return new InterruptResult(episode, outcome);
    }

    private boolean shouldProcess(double t) {
        Double rate = configuration.maxProcessingRateHz();
        if (rate == null || rate <= 0.0) {
            nextProcessingDue = null;
            return true;
        }
        double period = 1.0 / rate;
        if (nextProcessingDue == null) {
            nextProcessingDue = t + period;
            return true;
        }
        if (t + DECIMATION_EPSILON < nextProcessingDue) {
            return false;
        }
        nextProcessingDue += period;
        if (nextProcessingDue <= t) {
            nextProcessingDue = t + period;
        }
        return true;
    }

    private PostureUpdate passiveUpdate(double t, PostureEpisode episode, CalibrationOutcome outcome) {
        PostureEpisode pending = takePendingEpisode();
        if (pending != null && episode == null) {
            episode = pending;
        }
        return new PostureUpdate(t, state(), lastTilt, null, episode, outcome);
    }
}
