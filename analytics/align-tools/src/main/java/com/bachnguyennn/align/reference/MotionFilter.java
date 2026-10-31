package com.bachnguyennn.align.reference;

import static com.bachnguyennn.align.reference.Geometry.add;
import static com.bachnguyennn.align.reference.Geometry.length;
import static com.bachnguyennn.align.reference.Geometry.normalized;
import static com.bachnguyennn.align.reference.Geometry.scale;
import static com.bachnguyennn.align.reference.Geometry.sub;

import com.bachnguyennn.align.reference.Geometry.Vec3;

/**
 * Time-constant exponential smoothing of the head-frame gravity unit vector: an EMA with
 * alpha = 1 - exp(-dt / tau), renormalized to a unit vector.
 *
 * <p>Being time-based (not per-sample), the response is the same at any sample rate. The first
 * sample after construction or {@link #reset()} initializes the output.
 */
public final class MotionFilter {

    private Vec3 value;
    private Double lastTimestamp;

    public void reset() {
        value = null;
        lastTimestamp = null;
    }

    /** The current smoothed value, or null before the first sample. */
    public Vec3 value() {
        return value;
    }

    public Vec3 update(Vec3 gravityUnit, double timestamp, double timeConstant) {
        if (value == null || lastTimestamp == null) {
            value = gravityUnit;
            lastTimestamp = timestamp;
            return gravityUnit;
        }
        double dt = timestamp - lastTimestamp;
        if (dt < 0.0) {
            dt = 0.0;
        }
        double alpha;
        if (timeConstant <= 0.0) {
            alpha = 1.0;
        } else {
            alpha = 1.0 - StrictMath.exp(-dt / timeConstant);
        }
        Vec3 blended = add(value, scale(sub(gravityUnit, value), alpha));
        Vec3 result = normalized(blended);
        if (length(result) == 0.0) {
            result = gravityUnit;
        }
        value = result;
        lastTimestamp = timestamp;
        return result;
    }
}
