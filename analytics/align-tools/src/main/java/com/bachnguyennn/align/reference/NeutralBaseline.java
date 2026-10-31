package com.bachnguyennn.align.reference;

import com.bachnguyennn.align.reference.Geometry.Vec3;

/**
 * AlignCore {@code NeutralBaseline}; {@code capturedAt} is a monotonic timestamp here.
 * {@code learnedAxes} are the head axes learned from a guided nod for this earbud fit (D-017), or
 * null to use {@code PostureConfiguration.axes}. A neutral calibration always produces null.
 */
public record NeutralBaseline(Vec3 gravity, double capturedAt, int sampleCount, int version,
                              HeadAxisConvention learnedAxes) {

    /** A baseline without learned axes. */
    public NeutralBaseline(Vec3 gravity, double capturedAt, int sampleCount, int version) {
        this(gravity, capturedAt, sampleCount, version, null);
    }

    /** A copy with other learned axes (null = none) and version. */
    public NeutralBaseline withLearnedAxes(HeadAxisConvention axes, int newVersion) {
        return new NeutralBaseline(gravity, capturedAt, sampleCount, newVersion, axes);
    }
}
