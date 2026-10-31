package com.bachnguyennn.align.server.session;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.Objects;
import java.util.UUID;

/** A device's copy of one {@code MonitoringSession} (data-contracts.md). */
@Entity
@Table(name = "monitoring_session")
public class SessionEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "pk")
    private Long pk;

    @Column(name = "device_id", nullable = false, updatable = false)
    private UUID deviceId;

    /** The client's UUID ({@code MonitoringSession.id}). Unique per device. */
    @Column(name = "session_id", nullable = false, updatable = false)
    private UUID sessionId;

    @Column(name = "started_at", nullable = false)
    private Instant startedAt;

    @Column(name = "ended_at")
    private Instant endedAt;

    @Column(name = "monitored_duration_seconds", nullable = false)
    private double monitoredDurationSeconds;

    @Column(name = "within_threshold_seconds", nullable = false)
    private double withinThresholdSeconds;

    @Column(name = "sustained_deviation_seconds", nullable = false)
    private double sustainedDeviationSeconds;

    @Column(name = "reminder_count", nullable = false)
    private int reminderCount;

    @Column(name = "calibration_version", nullable = false)
    private int calibrationVersion;

    @Column(name = "sensor_availability_status", nullable = false, length = 16)
    private String sensorAvailabilityStatus;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    protected SessionEntity() {
    }

    public SessionEntity(UUID deviceId, UUID sessionId, Instant now) {
        this.deviceId = deviceId;
        this.sessionId = sessionId;
        this.createdAt = now;
        this.updatedAt = now;
    }

    /** True when every client field already equals {@code upload} (normalized). */
    boolean matches(SessionUpload upload) {
        return startedAt.equals(upload.startedAt())
                && Objects.equals(endedAt, upload.endedAt())
                && Double.compare(monitoredDurationSeconds, upload.monitoredDurationSeconds()) == 0
                && Double.compare(withinThresholdSeconds, upload.withinThresholdSeconds()) == 0
                && Double.compare(sustainedDeviationSeconds, upload.sustainedDeviationSeconds()) == 0
                && reminderCount == upload.reminderCount()
                && calibrationVersion == upload.calibrationVersion()
                && sensorAvailabilityStatus.equals(upload.sensorAvailabilityStatus());
    }

    void apply(SessionUpload upload) {
        startedAt = upload.startedAt();
        endedAt = upload.endedAt();
        monitoredDurationSeconds = upload.monitoredDurationSeconds();
        withinThresholdSeconds = upload.withinThresholdSeconds();
        sustainedDeviationSeconds = upload.sustainedDeviationSeconds();
        reminderCount = upload.reminderCount();
        calibrationVersion = upload.calibrationVersion();
        sensorAvailabilityStatus = upload.sensorAvailabilityStatus();
    }

    void touch(Instant now) {
        updatedAt = now;
    }

    public Long getPk() {
        return pk;
    }

    public UUID getDeviceId() {
        return deviceId;
    }

    public UUID getSessionId() {
        return sessionId;
    }

    public Instant getStartedAt() {
        return startedAt;
    }

    public Instant getEndedAt() {
        return endedAt;
    }

    public double getMonitoredDurationSeconds() {
        return monitoredDurationSeconds;
    }

    public double getWithinThresholdSeconds() {
        return withinThresholdSeconds;
    }

    public double getSustainedDeviationSeconds() {
        return sustainedDeviationSeconds;
    }

    public int getReminderCount() {
        return reminderCount;
    }

    public int getCalibrationVersion() {
        return calibrationVersion;
    }

    public String getSensorAvailabilityStatus() {
        return sensorAvailabilityStatus;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }
}
