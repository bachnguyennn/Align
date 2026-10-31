package com.bachnguyennn.align.reference;

import static org.junit.jupiter.api.Assertions.assertTrue;

import com.bachnguyennn.align.reference.Geometry.Vec3;

/** {@code pytest.approx} equivalents: default relative 1e-6 (absolute floor 1e-12), or an explicit tolerance. */
final class Approx {

    private Approx() {}

    /** {@code actual == pytest.approx(expected)}. */
    static void assertApprox(double expected, double actual) {
        assertWithin(expected, actual, Math.max(1e-6 * Math.abs(expected), 1e-12));
    }

    /** {@code actual == pytest.approx(expected, abs=abs)}. */
    static void assertApprox(double expected, double actual, double abs) {
        assertWithin(expected, actual, abs);
    }

    /** {@code actual == pytest.approx(expected, rel=rel)}. */
    static void assertApproxRel(double expected, double actual, double rel) {
        assertWithin(expected, actual, Math.max(rel * Math.abs(expected), 1e-12));
    }

    static void assertApprox(Vec3 expected, Vec3 actual) {
        assertApprox(expected.x(), actual.x());
        assertApprox(expected.y(), actual.y());
        assertApprox(expected.z(), actual.z());
    }

    static void assertApprox(Vec3 expected, Vec3 actual, double abs) {
        assertApprox(expected.x(), actual.x(), abs);
        assertApprox(expected.y(), actual.y(), abs);
        assertApprox(expected.z(), actual.z(), abs);
    }

    private static void assertWithin(double expected, double actual, double tolerance) {
        assertTrue(Math.abs(actual - expected) <= tolerance,
                () -> "expected " + expected + " ± " + tolerance + " but was " + actual);
    }
}
