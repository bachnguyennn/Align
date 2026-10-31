package com.bachnguyennn.align.server.settings;

import com.fasterxml.jackson.annotation.JsonInclude;
import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;

/**
 * The synced settings document: the app's {@code AppSettings} toggles plus the user-tunable part
 * of {@code PostureConfiguration} (data-contracts.md, "Settings"). Every field is optional; a
 * missing field means "app default". Not included: {@code axes} (the app always uses the package
 * default, D-011), the {@code NeutralBaseline} and learned axes (per earbud fit, D-017), and the
 * sensitivity preset (derived from the thresholds, D-013).
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record SettingsDocument(
        Boolean remindersEnabled,
        Boolean soundEnabled,
        Boolean hapticsEnabled,
        Boolean demoModeEnabled,
        @Valid Configuration configuration) {

    /** {@code PostureConfiguration} fields, same names and units (seconds, degrees, Hz). */
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public record Configuration(
            @DecimalMin("1") @DecimalMax("120") Double calibrationDuration,
            @DecimalMin("0.5") @DecimalMax("30") Double calibrationMaxSpreadDegrees,
            @DecimalMin("0.5") @DecimalMax("1") Double calibrationSpreadQuantile,
            @Min(1) @Max(100_000) Integer minimumCalibrationSamples,
            @DecimalMin("1") @DecimalMax("90") Double forwardThresholdDegrees,
            @DecimalMin("1") @DecimalMax("90") Double backwardThresholdDegrees,
            @DecimalMin("1") @DecimalMax("90") Double lateralThresholdDegrees,
            @DecimalMin("0") @DecimalMax("30") Double hysteresisDegrees,
            @DecimalMin("1") @DecimalMax("3600") Double sustainedDuration,
            @DecimalMin("0") @DecimalMax("86400") Double reminderCooldown,
            @DecimalMin("0") @DecimalMax("10") Double smoothingTimeConstant,
            @DecimalMin("1") @DecimalMax("1000") Double maxProcessingRateHz,
            @DecimalMin("0.01") @DecimalMax("60") Double maxSampleGap,
            @DecimalMin("1") @DecimalMax("120") Double axisCalibrationDuration,
            @DecimalMin("1") @DecimalMax("90") Double axisCalibrationMinimumNodDegrees,
            @DecimalMin("0") @DecimalMax("90") Double axisCalibrationMaxYawDegrees,
            @DecimalMin("0") @DecimalMax("10") Double axisCalibrationMaxOffAxisRatio) {
    }

    public static SettingsDocument empty() {
        return new SettingsDocument(null, null, null, null, null);
    }
}
