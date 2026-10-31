package com.bachnguyennn.align.reference;

import com.bachnguyennn.align.reference.Geometry.Quat;
import com.bachnguyennn.align.reference.Geometry.Vec3;

/** AlignCore {@code MotionSample}; {@code gravity} and {@code rotationRate} may be null. */
public record MotionSample(double timestamp, Quat attitude, Vec3 gravity, Vec3 rotationRate) {

    public MotionSample(double timestamp, Quat attitude, Vec3 gravity) {
        this(timestamp, attitude, gravity, null);
    }
}
