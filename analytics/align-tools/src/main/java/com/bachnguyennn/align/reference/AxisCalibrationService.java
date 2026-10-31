package com.bachnguyennn.align.reference;

import static com.bachnguyennn.align.reference.Geometry.DEGREES_PER_RADIAN;
import static com.bachnguyennn.align.reference.Geometry.cross;
import static com.bachnguyennn.align.reference.Geometry.dot;
import static com.bachnguyennn.align.reference.Geometry.length;
import static com.bachnguyennn.align.reference.Geometry.neg;
import static com.bachnguyennn.align.reference.Geometry.normalized;
import static com.bachnguyennn.align.reference.Geometry.scale;

import com.bachnguyennn.align.reference.Geometry.Vec3;
import java.util.ArrayList;
import java.util.List;

/**
 * Guided-nod axis calibration (D-017). Mirrors Swift {@code AxisCalibrationService}.
 *
 * <p>After {@link #begin()}, each smoothed gravity sample is turned into the head rotation vector
 * relative to the baseline gravity {@code g0}, exactly as the tilt estimate does
 * ({@code head = -rotationVector(g0, g)}). It is perpendicular to {@code g0}, so heading never
 * contributes. Samples whose rotation is at least {@link #MOTION_FLOOR_DEGREES} are kept.
 *
 * <p>The attempt finishes on the first sample at which the head is back within
 * {@link #RETURN_DEGREES} of neutral after a peak of at least
 * {@code axisCalibrationMinimumNodDegrees}, or once {@code axisCalibrationDuration} has elapsed
 * since the first sample. Without such a peak it fails with {@code noNodDetected}. Otherwise the
 * forward axis line is fitted to the kept rotation vectors in the baseline plane, using the 2-D
 * basis {@code e1} = configured forward axis projected onto the plane, {@code e2} =
 * normalized({@code g0 x e1}):
 * <ul>
 *   <li>{@link LineFit#PRINCIPAL_AXIS} (default): the principal axis of the scatter matrix
 *       {@code sum v v^T}, angle {@code 0.5 atan2(2 Sab, Saa - Sbb)} from {@code e1}. Squared
 *       weighting lets the large nod samples dominate the small sway samples, and a line through
 *       the origin is fitted whether the user nods down, up, or both.</li>
 *   <li>{@link LineFit#SIGNED_SUM}: the sum of the vectors after flipping those with a negative
 *       {@code e1} component, and {@link LineFit#CENTERED_PRINCIPAL_AXIS}: the principal axis of
 *       the mean-centred vectors. Both are kept for the evaluation only (results/evaluation.md,
 *       D-017 (ii-b)); Swift implements only the default.</li>
 * </ul>
 * Both angles lie in (-90 deg, 90 deg], so the learned forward axis has a non-negative dot product
 * with {@code e1}: the sign comes from the default convention and a nod down or up both work.
 * Lateral = normalized({@code g0 x forward}) (for the defaults with {@code g0 = (0, 0, -1)}:
 * forward (-1, 0, 0), lateral (0, 1, 0)). Rejected with {@code inconsistentMotion} if the fitted
 * angle exceeds {@code axisCalibrationMaxYawDegrees}, or if the off-axis ratio
 * {@code sum |v . lateral| / sum |v . forward|} exceeds {@code axisCalibrationMaxOffAxisRatio}.
 */
public final class AxisCalibrationService {

    /** Rotations below this (degrees) are sway or noise and are not used for the fit. */
    public static final double MOTION_FLOOR_DEGREES = 3.0;
    /** After a valid peak, the attempt finishes once the head is back within this tilt (degrees). */
    public static final double RETURN_DEGREES = 5.0;

    /** How the forward axis line is fitted to the rotation vectors. */
    public enum LineFit { PRINCIPAL_AXIS, SIGNED_SUM, CENTERED_PRINCIPAL_AXIS }

    /** Result of feeding one sample: in progress, succeeded (axes), or failed. */
    public record AxisCalibrationStep(boolean finished, double progress, HeadAxisConvention axes,
                                      AxisCalibrationFailure failure) {

        static AxisCalibrationStep inProgress(double progress) {
            return new AxisCalibrationStep(false, progress, null, null);
        }

        static AxisCalibrationStep failed(AxisCalibrationFailure failure) {
            return new AxisCalibrationStep(true, 1.0, null, failure);
        }

        static AxisCalibrationStep succeeded(HeadAxisConvention axes) {
            return new AxisCalibrationStep(true, 1.0, axes, null);
        }
    }

    /**
     * A fitted axis line: {@code axes} (null if the basis is degenerate), its signed angle from the
     * configured forward axis in the baseline plane (positive toward {@code g0 x e1}), and the
     * off-axis ratio over the {@code samplesUsed} rotation vectors.
     */
    public record Fit(HeadAxisConvention axes, double yawDegrees, double offAxisRatio, int samplesUsed) {}

    private final LineFit lineFit;
    private boolean isActive = false;
    private Double startTimestamp;
    private Double lastTimestamp;
    private double peakDegrees = 0.0;
    private List<Vec3> rotations = new ArrayList<>();

    public AxisCalibrationService() {
        this(LineFit.PRINCIPAL_AXIS);
    }

    public AxisCalibrationService(LineFit lineFit) {
        this.lineFit = lineFit != null ? lineFit : LineFit.PRINCIPAL_AXIS;
    }

    public boolean isActive() {
        return isActive;
    }

    /** Largest rotation from neutral seen in the current attempt (degrees). */
    public double peakDegrees() {
        return peakDegrees;
    }

    public void begin() {
        isActive = true;
        startTimestamp = null;
        lastTimestamp = null;
        peakDegrees = 0.0;
        rotations = new ArrayList<>();
    }

    public void cancel() {
        isActive = false;
        startTimestamp = null;
        lastTimestamp = null;
        peakDegrees = 0.0;
        rotations = new ArrayList<>();
    }

    /** 0..1 while active; 0 before the first sample. */
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

    /** Motion floor actually used: {@link #MOTION_FLOOR_DEGREES}, at most half the minimum nod. */
    public static double floorDegrees(double minimumNodDegrees) {
        return Math.min(MOTION_FLOOR_DEGREES, 0.5 * minimumNodDegrees);
    }

    /** Return-to-neutral level actually used: {@link #RETURN_DEGREES}, at most half the minimum nod. */
    public static double returnDegrees(double minimumNodDegrees) {
        return Math.min(RETURN_DEGREES, 0.5 * minimumNodDegrees);
    }

    public AxisCalibrationStep add(Vec3 gravityUnit, double timestamp, Vec3 baselineGravity,
                                   PostureConfiguration config) {
        if (startTimestamp == null) {
            startTimestamp = timestamp;
        }
        lastTimestamp = timestamp;
        Vec3 g0 = normalized(baselineGravity);
        Vec3 head = neg(Tilt.rotationVector(g0, gravityUnit));
        double angle = length(head) * DEGREES_PER_RADIAN;
        double minimumNod = config.axisCalibrationMinimumNodDegrees();
        if (angle >= floorDegrees(minimumNod)) {
            rotations.add(head);
        }
        if (angle > peakDegrees) {
            peakDegrees = angle;
        }
        boolean validPeak = peakDegrees >= minimumNod;
        boolean returned = validPeak && angle <= returnDegrees(minimumNod);
        double elapsed = timestamp - startTimestamp;
        double duration = config.axisCalibrationDuration();
        if (!returned && elapsed + Model.TIME_EPSILON < duration) {
            return AxisCalibrationStep.inProgress(progress(duration));
        }

        List<Vec3> used = rotations;
        cancel();
        if (!validPeak || used.isEmpty()) {
            return AxisCalibrationStep.failed(AxisCalibrationFailure.NO_NOD_DETECTED);
        }
        Fit fit = fit(used, g0, config.axes(), lineFit);
        // Written as !(x <= limit) so that NaN is rejected, exactly like Swift's guard.
        if (fit.axes() == null
                || !(Math.abs(fit.yawDegrees()) <= config.axisCalibrationMaxYawDegrees())
                || !(fit.offAxisRatio() <= config.axisCalibrationMaxOffAxisRatio())) {
            return AxisCalibrationStep.failed(AxisCalibrationFailure.INCONSISTENT_MOTION);
        }
        return AxisCalibrationStep.succeeded(fit.axes());
    }

    /** The 2-D basis of the baseline plane: {@code e1} = projected reference forward, {@code e2} = g0 x e1. */
    private static Vec3[] basis(Vec3 baselineUnit, HeadAxisConvention reference) {
        Vec3 e1 = Tilt.baselinePlaneAxis(reference.forwardAxis(), baselineUnit);
        Vec3 e2 = normalized(cross(baselineUnit, e1));
        return new Vec3[] {e1, e2};
    }

    /** Fits the forward axis line to non-empty {@code rotations} (head rotation vectors, radians). */
    public static Fit fit(List<Vec3> rotations, Vec3 baselineUnit, HeadAxisConvention reference, LineFit method) {
        Vec3[] b = basis(baselineUnit, reference);
        Vec3 e1 = b[0];
        Vec3 e2 = b[1];
        if (length(e2) == 0.0) {
            return new Fit(null, 90.0, Double.POSITIVE_INFINITY, rotations.size());
        }
        double angle;
        if (method == LineFit.SIGNED_SUM) {
            double sa = 0.0;
            double sb = 0.0;
            for (Vec3 v : rotations) {
                double a = dot(v, e1);
                double c = dot(v, e2);
                if (a < 0.0) {
                    a = -a;
                    c = -c;
                }
                sa += a;
                sb += c;
            }
            angle = StrictMath.atan2(sb, sa);
        } else {
            double ma = 0.0;
            double mc = 0.0;
            if (method == LineFit.CENTERED_PRINCIPAL_AXIS) {
                for (Vec3 v : rotations) {
                    ma += dot(v, e1);
                    mc += dot(v, e2);
                }
                ma /= rotations.size();
                mc /= rotations.size();
            }
            double saa = 0.0;
            double sbb = 0.0;
            double sab = 0.0;
            for (Vec3 v : rotations) {
                double a = dot(v, e1) - ma;
                double c = dot(v, e2) - mc;
                saa += a * a;
                sbb += c * c;
                sab += a * c;
            }
            angle = 0.5 * StrictMath.atan2(2.0 * sab, saa - sbb);
        }
        Vec3 forward = normalized(Geometry.add(scale(e1, StrictMath.cos(angle)), scale(e2, StrictMath.sin(angle))));
        Vec3 lateral = normalized(cross(baselineUnit, forward));
        double along = 0.0;
        double across = 0.0;
        for (Vec3 v : rotations) {
            along += Math.abs(dot(v, forward));
            across += Math.abs(dot(v, lateral));
        }
        double ratio = along > 0.0 ? across / along : Double.POSITIVE_INFINITY;
        return new Fit(new HeadAxisConvention(forward, lateral), angle * DEGREES_PER_RADIAN, ratio, rotations.size());
    }

    /**
     * Signed angle (degrees) of {@code forwardAxis} from the reference forward axis, both projected
     * onto the baseline plane; positive toward {@code g0 x e1} (the default lateral axis), i.e. a
     * right-hand rotation about the baseline gravity (down).
     */
    public static double signedYawDegrees(Vec3 forwardAxis, Vec3 baselineGravity, HeadAxisConvention reference) {
        Vec3 g0 = normalized(baselineGravity);
        Vec3[] b = basis(g0, reference);
        Vec3 f = Tilt.baselinePlaneAxis(forwardAxis, g0);
        return StrictMath.atan2(dot(f, b[1]), dot(f, b[0])) * DEGREES_PER_RADIAN;
    }
}
