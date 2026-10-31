package com.bachnguyennn.align.server.session;

import com.bachnguyennn.align.server.config.ApiLimits;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import java.time.Instant;
import java.util.UUID;

/** One {@code PostureEvent} in a {@link EventBatch}. */
public record EventUpload(
        @NotNull UUID id,
        @NotNull Instant startedAt,
        @NotNull Instant endedAt,
        @NotNull @Pattern(regexp = "forward|backward|left|right",
                message = "must be one of forward, backward, left, right") String deviationType,
        @NotNull @DecimalMin("0") @DecimalMax(ApiLimits.MAX_EVENT_SECONDS_TEXT) Double durationSeconds,
        @NotNull @DecimalMin("0") @DecimalMax(ApiLimits.MAX_PEAK_DEGREES_TEXT) Double peakDeviationDegrees,
        @NotNull Boolean reminderTriggered) {

    EventUpload normalized() {
        return new EventUpload(id, SessionUpload.micros(startedAt), SessionUpload.micros(endedAt), deviationType,
                durationSeconds, peakDeviationDegrees, reminderTriggered);
    }
}
