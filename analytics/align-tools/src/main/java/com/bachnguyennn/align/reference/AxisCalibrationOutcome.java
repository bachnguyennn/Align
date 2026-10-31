package com.bachnguyennn.align.reference;

/**
 * AlignCore {@code AxisCalibrationOutcome}: {@code succeeded} carries the learned axes; otherwise
 * {@code failure} is set.
 */
public record AxisCalibrationOutcome(boolean succeeded, HeadAxisConvention axes, AxisCalibrationFailure failure) {

    public static AxisCalibrationOutcome success(HeadAxisConvention axes) {
        return new AxisCalibrationOutcome(true, axes, null);
    }

    public static AxisCalibrationOutcome failed(AxisCalibrationFailure failure) {
        return new AxisCalibrationOutcome(false, null, failure);
    }

    /** "succeeded" or the AxisCalibrationFailure raw value, as used in fixture JSON. */
    public String name() {
        return succeeded ? "succeeded" : String.valueOf(failure);
    }
}
