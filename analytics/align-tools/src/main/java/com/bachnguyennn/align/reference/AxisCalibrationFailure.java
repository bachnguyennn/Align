package com.bachnguyennn.align.reference;

/** AlignCore {@code AxisCalibrationFailure} (D-017). */
public enum AxisCalibrationFailure {
    /** {@code beginAxisCalibration()} was called without a neutral baseline. */
    NEEDS_BASELINE("needsBaseline"),
    /** The head never tilted {@code axisCalibrationMinimumNodDegrees} away from neutral in time. */
    NO_NOD_DETECTED("noNodDetected"),
    /** Not a single forward/backward nod: too much sideways motion, or too far from the default axis. */
    INCONSISTENT_MOTION("inconsistentMotion"),
    SENSOR_INTERRUPTED("sensorInterrupted");

    private final String rawValue;

    AxisCalibrationFailure(String rawValue) {
        this.rawValue = rawValue;
    }

    /** The Swift raw value, as used in fixture JSON. */
    public String rawValue() {
        return rawValue;
    }

    @Override
    public String toString() {
        return rawValue;
    }
}
