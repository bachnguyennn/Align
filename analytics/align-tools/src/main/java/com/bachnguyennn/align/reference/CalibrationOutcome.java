package com.bachnguyennn.align.reference;

/** {@code succeeded} carries the baseline; otherwise {@code failure} is set. */
public record CalibrationOutcome(boolean succeeded, NeutralBaseline baseline, CalibrationFailure failure) {

    public static CalibrationOutcome success(NeutralBaseline baseline) {
        return new CalibrationOutcome(true, baseline, null);
    }

    public static CalibrationOutcome failed(CalibrationFailure failure) {
        return new CalibrationOutcome(false, null, failure);
    }

    /** "succeeded" or the CalibrationFailure raw value, as used in fixture JSON. */
    public String name() {
        return succeeded ? "succeeded" : String.valueOf(failure);
    }
}
