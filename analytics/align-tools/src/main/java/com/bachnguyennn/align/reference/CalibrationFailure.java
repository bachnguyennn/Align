package com.bachnguyennn.align.reference;

/** AlignCore {@code CalibrationFailure}. */
public enum CalibrationFailure {
    TOO_MUCH_MOVEMENT("tooMuchMovement"),
    INSUFFICIENT_SAMPLES("insufficientSamples"),
    SENSOR_INTERRUPTED("sensorInterrupted");

    private final String rawValue;

    CalibrationFailure(String rawValue) {
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
