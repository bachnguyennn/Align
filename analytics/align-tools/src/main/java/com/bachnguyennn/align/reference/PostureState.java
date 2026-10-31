package com.bachnguyennn.align.reference;

/**
 * AlignCore {@code PostureState}: {@code progress} is set for {@code calibrating},
 * {@code direction} and {@code since} for {@code deviating} and {@code sustainedTilt}.
 */
public record PostureState(Kind kind, Double progress, TiltDirection direction, Double since) {

    /** PostureState case names. */
    public enum Kind {
        UNAVAILABLE("unavailable"),
        NEEDS_CALIBRATION("needsCalibration"),
        CALIBRATING("calibrating"),
        NEUTRAL("neutral"),
        DEVIATING("deviating"),
        SUSTAINED_TILT("sustainedTilt");

        private final String caseName;

        Kind(String caseName) {
            this.caseName = caseName;
        }

        /** The Swift case name, as used in fixture JSON ({@code finalState}). */
        public String caseName() {
            return caseName;
        }

        @Override
        public String toString() {
            return caseName;
        }
    }

    public static PostureState of(Kind kind) {
        return new PostureState(kind, null, null, null);
    }

    public static PostureState calibrating(double progress) {
        return new PostureState(Kind.CALIBRATING, progress, null, null);
    }

    public static PostureState deviating(TiltDirection direction, double since) {
        return new PostureState(Kind.DEVIATING, null, direction, since);
    }

    public static PostureState sustainedTilt(TiltDirection direction, double since) {
        return new PostureState(Kind.SUSTAINED_TILT, null, direction, since);
    }
}
