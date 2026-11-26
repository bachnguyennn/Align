package com.bachnguyennn.align.reference;

import static com.bachnguyennn.align.reference.Geometry.ZERO;
import static com.bachnguyennn.align.reference.Geometry.angleBetweenDegrees;
import static com.bachnguyennn.align.reference.Geometry.length;
import static com.bachnguyennn.align.reference.Geometry.normalized;

import com.bachnguyennn.align.reference.Geometry.Vec3;
import java.util.ArrayList;
import java.util.List;

/**
 * Neutral-baseline calibration. Collects {@code calibrationDuration} seconds of smoothed gravity,
 * measured from the first sample after the countdown. Fails with insufficientSamples if fewer than
 * {@code minimumCalibrationSamples} were collected.
 *
 * <p>Countdown (D-022): the first sample after {@link #begin()} starts a "get ready" countdown of
 * {@code calibrationCountdown} seconds. Samples with t - countdownStart < countdown are discarded
 * (the user is still looking down at the phone); the first sample at or after the end of the
 * countdown is the first sample of the hold. Progress stays 0 during the countdown. With a
 * countdown of 0 the first sample starts the hold, exactly as before D-022.
 *
 * <p>Spread rule (D-017): let {@code m} be the normalized mean of all samples and the inliers the
 * samples within {@code calibrationMaxSpreadDegrees} of {@code m}. Fails with tooMuchMovement
 * unless the inliers are at least {@code calibrationSpreadQuantile} of the samples (1.0 = the v1
 * rule "every sample"). Baseline = normalized mean of the inliers, so a brief fidget that the
 * quantile tolerates does not bias the baseline. When every sample is an inlier this is exactly
 * {@code m} (same sum in the same order), i.e. identical to v1.
 *
 * <p>Drift rule (D-020), checked after the spread rule: fails with tooMuchMovement if the
 * normalized mean gravity of the inliers in the first {@code calibrationDriftWindow} seconds
 * (t - start ≤ window) and that of the inliers in the last {@code calibrationDriftWindow}
 * seconds (last - t ≤ window) are more than {@code calibrationMaxDriftDegrees} apart, or if
 * either window has no inliers. It catches a slow slouch, which the spread rule cannot (every
 * sample stays near the mean of the ramp); using inliers only, a brief fidget at either end
 * does not count as drift.
 */
public final class CalibrationService {

    /** Result of feeding one sample: in progress, succeeded (mean gravity), or failed. */
    public record CalibrationStep(boolean finished, double progress, Vec3 meanGravity, int sampleCount,
                                  CalibrationFailure failure) {

        static CalibrationStep inProgress(double progress) {
            return new CalibrationStep(false, progress, null, 0, null);
        }

        static CalibrationStep failed(int sampleCount, CalibrationFailure failure) {
            return new CalibrationStep(true, 1.0, null, sampleCount, failure);
        }
    }

    private boolean isActive = false;
    private Double countdownStart;
    private Double startTimestamp;
    private Double lastTimestamp;
    private List<Vec3> samples = new ArrayList<>();
    private List<Double> timestamps = new ArrayList<>();

    /** {@link #driftDegrees(List, List, List, double)} with every sample counted as an inlier. */
    public static double driftDegrees(List<Vec3> gravities, List<Double> times, double window) {
        List<Boolean> all = new ArrayList<>();
        for (int i = 0; i < gravities.size(); i++) {
            all.add(true);
        }
        return driftDegrees(gravities, times, all, window);
    }

    /**
     * Angle (degrees) between the normalized mean of the inliers with t - first ≤ window and that
     * of the inliers with last - t ≤ window (D-020); {@code first} and {@code last} are the first
     * and last timestamps of all samples. NaN if either window has no inliers (the caller then
     * fails). {@code gravities}, {@code times} and {@code inliers} are non-empty and parallel;
     * times are in increasing order.
     */
    public static double driftDegrees(List<Vec3> gravities, List<Double> times, List<Boolean> inliers,
                                      double window) {
        double first = times.get(0);
        double last = times.get(times.size() - 1);
        Vec3 head = ZERO;
        Vec3 tail = ZERO;
        int headCount = 0;
        int tailCount = 0;
        for (int i = 0; i < gravities.size(); i++) {
            if (!inliers.get(i)) {
                continue;
            }
            double t = times.get(i);
            if (t - first <= window + Model.TIME_EPSILON) {
                head = Geometry.add(head, gravities.get(i));
                headCount++;
            }
            if (last - t <= window + Model.TIME_EPSILON) {
                tail = Geometry.add(tail, gravities.get(i));
                tailCount++;
            }
        }
        if (headCount == 0 || tailCount == 0) {
            return Double.NaN;
        }
        return angleBetweenDegrees(normalized(head), normalized(tail));
    }

    /** Tolerance of the quantile comparison, so that e.g. 225 of 250 samples count as 0.9. */
    public static final double QUANTILE_EPSILON = 1e-9;

    /** True if {@code inliers} of {@code count} samples reach {@code quantile} (clamped to [0, 1]). */
    public static boolean hasEnoughInliers(int inliers, int count, double quantile) {
        double q = Math.min(1.0, Math.max(0.0, quantile));
        return inliers + QUANTILE_EPSILON * count >= q * count;
    }

    public boolean isActive() {
        return isActive;
    }

    public void begin() {
        isActive = true;
        countdownStart = null;
        startTimestamp = null;
        lastTimestamp = null;
        samples = new ArrayList<>();
        timestamps = new ArrayList<>();
    }

    public void cancel() {
        isActive = false;
        countdownStart = null;
        startTimestamp = null;
        lastTimestamp = null;
        samples = new ArrayList<>();
        timestamps = new ArrayList<>();
    }

    /**
     * Seconds left in the countdown (D-022): the whole countdown before the first sample, then
     * countdown - (last - countdownStart), never below 0. 0 once the hold has started or when not
     * active.
     */
    public double countdownRemaining(double countdown) {
        if (!isActive || startTimestamp != null) {
            return 0.0;
        }
        if (countdownStart == null || lastTimestamp == null) {
            return Math.max(0.0, countdown);
        }
        return Math.max(0.0, countdown - (lastTimestamp - countdownStart));
    }

    /** True while active and the hold has not started (the countdown is running). */
    public boolean isCountingDown() {
        return isActive && startTimestamp == null;
    }

    public double progress(double duration) {
        if (!isActive || startTimestamp == null || lastTimestamp == null) {
            return 0.0;
        }
        if (duration <= 0.0) {
            return 1.0;
        }
        double p = (lastTimestamp - startTimestamp) / duration;
        return Math.min(1.0, Math.max(0.0, p));
    }

    public CalibrationStep add(Vec3 gravityUnit, double timestamp, PostureConfiguration config) {
        if (countdownStart == null) {
            countdownStart = timestamp;
        }
        lastTimestamp = timestamp;
        if (startTimestamp == null) {
            if (timestamp - countdownStart + Model.TIME_EPSILON < config.calibrationCountdown()) {
                return CalibrationStep.inProgress(0.0);
            }
            startTimestamp = timestamp;
        }
        samples.add(gravityUnit);
        timestamps.add(timestamp);
        double elapsed = timestamp - startTimestamp;
        double duration = config.calibrationDuration();
        if (elapsed + Model.TIME_EPSILON < duration) {
            return CalibrationStep.inProgress(progress(duration));
        }

        List<Vec3> collected = samples;
        List<Double> times = timestamps;
        cancel();
        int count = collected.size();
        if (count < config.minimumCalibrationSamples()) {
            return CalibrationStep.failed(count, CalibrationFailure.INSUFFICIENT_SAMPLES);
        }
        Vec3 total = ZERO;
        for (Vec3 g : collected) {
            total = Geometry.add(total, g);
        }
        Vec3 mean = normalized(total);
        if (length(mean) == 0.0) {
            return CalibrationStep.failed(count, CalibrationFailure.TOO_MUCH_MOVEMENT);
        }
        double limit = config.calibrationMaxSpreadDegrees();
        int inliers = 0;
        Vec3 inlierTotal = ZERO;
        List<Boolean> isInlier = new ArrayList<>(count);
        for (Vec3 g : collected) {
            boolean inlier = angleBetweenDegrees(g, mean) <= limit;
            isInlier.add(inlier);
            if (inlier) {
                inliers++;
                inlierTotal = Geometry.add(inlierTotal, g);
            }
        }
        if (!hasEnoughInliers(inliers, count, config.calibrationSpreadQuantile())) {
            return CalibrationStep.failed(count, CalibrationFailure.TOO_MUCH_MOVEMENT);
        }
        // Written as !(x <= limit) so that NaN (a window without inliers) is rejected, exactly like Swift.
        double drift = driftDegrees(collected, times, isInlier, config.calibrationDriftWindow());
        if (!(drift <= config.calibrationMaxDriftDegrees())) {
            return CalibrationStep.failed(count, CalibrationFailure.TOO_MUCH_MOVEMENT);
        }
        Vec3 baseline = inliers == count ? mean : normalized(inlierTotal);
        if (length(baseline) == 0.0) {
            return CalibrationStep.failed(count, CalibrationFailure.TOO_MUCH_MOVEMENT);
        }
        return new CalibrationStep(true, 1.0, baseline, count, null);
    }
}
