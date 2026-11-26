package com.bachnguyennn.align.reference;

/** Configurations shared by the unit tests. */
final class TestConfigs {

    /**
     * The defaults without the D-022 "get ready" countdown: the calibration hold starts on the
     * first sample, as every unit test written before D-022 assumes. The countdown has its own
     * tests in {@link CalibrationCountdownTest}.
     */
    static final PostureConfiguration NO_COUNTDOWN =
            PostureConfiguration.DEFAULT.replacing(b -> b.calibrationCountdown(0.0));

    private TestConfigs() {}
}
