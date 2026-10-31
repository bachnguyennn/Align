package com.bachnguyennn.align.reference;

/**
 * Constants of {@code model.py}. The model.py types are top-level records and enums in this
 * package: {@link TiltDirection}, {@link CalibrationFailure}, {@link PostureState},
 * {@link MotionSample}, {@link TiltEstimate}, {@link NeutralBaseline}, {@link CalibrationOutcome},
 * {@link ReminderDecision}, {@link PostureEpisode}, {@link PostureUpdate},
 * {@link HeadAxisConvention} and {@link PostureConfiguration}.
 */
public final class Model {

    /**
     * Tolerance used when comparing elapsed times with durations, so that e.g. 45.04 - 15.04
     * (= 29.999999999999996 in IEEE doubles) counts as 30 s. Identical constant in Swift.
     */
    public static final double TIME_EPSILON = 1e-9;

    private Model() {}
}
