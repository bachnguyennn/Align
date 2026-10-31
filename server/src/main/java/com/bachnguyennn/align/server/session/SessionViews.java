package com.bachnguyennn.align.server.session;

import com.fasterxml.jackson.annotation.JsonInclude;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

/** Response bodies of the session endpoints. */
public final class SessionViews {

    private SessionViews() {
    }

    /** A stored session. {@code events} is present only on {@code GET /sessions/{id}}. */
    public record SessionView(
            UUID id,
            Instant startedAt,
            Instant endedAt,
            double monitoredDurationSeconds,
            double withinThresholdSeconds,
            double sustainedDeviationSeconds,
            int reminderCount,
            int calibrationVersion,
            String sensorAvailabilityStatus,
            Instant createdAt,
            Instant updatedAt,
            @JsonInclude(JsonInclude.Include.NON_NULL) List<EventView> events) {

        static SessionView of(SessionEntity s, List<EventView> events) {
            return new SessionView(s.getSessionId(), s.getStartedAt(), s.getEndedAt(),
                    s.getMonitoredDurationSeconds(), s.getWithinThresholdSeconds(),
                    s.getSustainedDeviationSeconds(), s.getReminderCount(), s.getCalibrationVersion(),
                    s.getSensorAvailabilityStatus(), s.getCreatedAt(), s.getUpdatedAt(), events);
        }
    }

    public record EventView(
            UUID id,
            Instant startedAt,
            Instant endedAt,
            String deviationType,
            double durationSeconds,
            double peakDeviationDegrees,
            boolean reminderTriggered,
            Instant createdAt,
            Instant updatedAt) {

        static EventView of(PostureEventEntity e) {
            return new EventView(e.getEventId(), e.getStartedAt(), e.getEndedAt(), e.getDeviationType(),
                    e.getDurationSeconds(), e.getPeakDeviationDegrees(), e.isReminderTriggered(),
                    e.getCreatedAt(), e.getUpdatedAt());
        }
    }

    /** One page of {@code GET /sessions}. {@code nextCursor} is null on the last page. */
    public record SessionPage(List<SessionView> items, String nextCursor) {
    }

    /** Result of an event batch upsert. */
    public record EventBatchResult(int created, int updated, int unchanged) {
    }
}
