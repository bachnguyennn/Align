package com.bachnguyennn.align.reference;

import com.bachnguyennn.align.reference.Geometry.Vec3;

/** AlignCore {@code NeutralBaseline}; {@code capturedAt} is a monotonic timestamp here. */
public record NeutralBaseline(Vec3 gravity, double capturedAt, int sampleCount, int version) {}
