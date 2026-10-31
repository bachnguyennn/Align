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
 * measured from the first sample it receives. Fails with insufficientSamples if fewer than
 * {@code minimumCalibrationSamples} were collected.
 *
 * <p>Spread rule (D-017): let {@code m} be the normalized mean of all samples and the inliers the
 * samples within {@code calibrationMaxSpreadDegrees} of {@code m}. Fails with tooMuchMovement
 * unless the inliers are at least {@code calibrationSpreadQuantile} of the samples (1.0 = the v1
 * rule "every sample"). Baseline = normalized mean of the inliers, so a brief fidget that the
 * quantile tolerates does not bias the baseline. When every sample is an inlier this is exactly
 * {@code m} (same sum in the same order), i.e. identical to v1.
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
    private Double startTimestamp;
    private Double lastTimestamp;
    private List<Vec3> samples = new ArrayList<>();

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
        startTimestamp = null;
        lastTimestamp = null;
        samples = new ArrayList<>();
    }

    public void cancel() {
        isActive = false;
        startTimestamp = null;
        lastTimestamp = null;
        samples = new ArrayList<>();
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
        if (startTimestamp == null) {
            startTimestamp = timestamp;
        }
        lastTimestamp = timestamp;
        samples.add(gravityUnit);
        double elapsed = timestamp - startTimestamp;
        double duration = config.calibrationDuration();
        if (elapsed + Model.TIME_EPSILON < duration) {
            return CalibrationStep.inProgress(progress(duration));
        }

        List<Vec3> collected = samples;
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
        for (Vec3 g : collected) {
            if (angleBetweenDegrees(g, mean) <= limit) {
                inliers++;
                inlierTotal = Geometry.add(inlierTotal, g);
            }
        }
        if (!hasEnoughInliers(inliers, count, config.calibrationSpreadQuantile())) {
            return CalibrationStep.failed(count, CalibrationFailure.TOO_MUCH_MOVEMENT);
        }
        Vec3 baseline = inliers == count ? mean : normalized(inlierTotal);
        if (length(baseline) == 0.0) {
            return CalibrationStep.failed(count, CalibrationFailure.TOO_MUCH_MOVEMENT);
        }
        return new CalibrationStep(true, 1.0, baseline, count, null);
    }
}
