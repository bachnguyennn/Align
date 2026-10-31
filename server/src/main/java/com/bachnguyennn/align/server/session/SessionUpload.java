package com.bachnguyennn.align.server.session;

import com.bachnguyennn.align.server.config.ApiLimits;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.UUID;

/**
 * Body of {@code PUT /api/v1/sessions/{id}}: the client's {@code MonitoringSession} without its
 * events. {@code id} is optional; when present it must equal the path id.
 */
public record SessionUpload(
        UUID id,
        @NotNull Instant startedAt,
        Instant endedAt,
        @NotNull @DecimalMin("0") @DecimalMax(ApiLimits.MAX_SESSION_SECONDS_TEXT) Double monitoredDurationSeconds,
        @NotNull @DecimalMin("0") @DecimalMax(ApiLimits.MAX_SESSION_SECONDS_TEXT) Double withinThresholdSeconds,
        @NotNull @DecimalMin("0") @DecimalMax(ApiLimits.MAX_SESSION_SECONDS_TEXT) Double sustainedDeviationSeconds,
        @NotNull @Min(0) @Max(ApiLimits.MAX_REMINDERS_PER_SESSION) Integer reminderCount,
        @NotNull @Min(0) Integer calibrationVersion,
        @NotNull @Pattern(regexp = "real|mock|unavailable", message = "must be one of real, mock, unavailable")
        String sensorAvailabilityStatus) {

    /** Timestamps truncated to microseconds (database precision), so re-uploads compare equal. */
    SessionUpload normalized() {
        return new SessionUpload(id, micros(startedAt), micros(endedAt), monitoredDurationSeconds,
                withinThresholdSeconds, sustainedDeviationSeconds, reminderCount, calibrationVersion,
                sensorAvailabilityStatus);
    }

    static Instant micros(Instant instant) {
        return instant == null ? null : instant.truncatedTo(ChronoUnit.MICROS);
    }
}
