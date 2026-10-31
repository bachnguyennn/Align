package com.bachnguyennn.align.server.session;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

/** A device's copy of one {@code PostureEvent} (one sustained-tilt episode). */
@Entity
@Table(name = "posture_event")
public class PostureEventEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "pk")
    private Long pk;

    @Column(name = "session_pk", nullable = false, updatable = false)
    private Long sessionPk;

    @Column(name = "device_id", nullable = false, updatable = false)
    private UUID deviceId;

    /** The client's UUID ({@code PostureEvent.id}). Unique per device. */
    @Column(name = "event_id", nullable = false, updatable = false)
    private UUID eventId;

    @Column(name = "started_at", nullable = false)
    private Instant startedAt;

    @Column(name = "ended_at", nullable = false)
    private Instant endedAt;

    @Column(name = "deviation_type", nullable = false, length = 16)
    private String deviationType;

    @Column(name = "duration_seconds", nullable = false)
    private double durationSeconds;

    @Column(name = "peak_deviation_degrees", nullable = false)
    private double peakDeviationDegrees;

    @Column(name = "reminder_triggered", nullable = false)
    private boolean reminderTriggered;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    protected PostureEventEntity() {
    }

    PostureEventEntity(Long sessionPk, UUID deviceId, UUID eventId, Instant now) {
        this.sessionPk = sessionPk;
        this.deviceId = deviceId;
        this.eventId = eventId;
        this.createdAt = now;
        this.updatedAt = now;
    }

    boolean matches(EventUpload upload) {
        return startedAt.equals(upload.startedAt())
                && endedAt.equals(upload.endedAt())
                && deviationType.equals(upload.deviationType())
                && Double.compare(durationSeconds, upload.durationSeconds()) == 0
                && Double.compare(peakDeviationDegrees, upload.peakDeviationDegrees()) == 0
                && reminderTriggered == upload.reminderTriggered();
    }

    void apply(EventUpload upload, Instant now) {
        startedAt = upload.startedAt();
        endedAt = upload.endedAt();
        deviationType = upload.deviationType();
        durationSeconds = upload.durationSeconds();
        peakDeviationDegrees = upload.peakDeviationDegrees();
        reminderTriggered = upload.reminderTriggered();
        updatedAt = now;
    }

    public Long getSessionPk() {
        return sessionPk;
    }

    public UUID getDeviceId() {
        return deviceId;
    }

    public UUID getEventId() {
        return eventId;
    }

    public Instant getStartedAt() {
        return startedAt;
    }

    public Instant getEndedAt() {
        return endedAt;
    }

    public String getDeviationType() {
        return deviationType;
    }

    public double getDurationSeconds() {
        return durationSeconds;
    }

    public double getPeakDeviationDegrees() {
        return peakDeviationDegrees;
    }

    public boolean isReminderTriggered() {
        return reminderTriggered;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }
}
