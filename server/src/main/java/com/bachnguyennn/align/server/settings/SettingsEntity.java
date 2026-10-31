package com.bachnguyennn.align.server.settings;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

/**
 * One settings document per device. {@code version} starts at 1 and is bumped by a conditional
 * update in {@link SettingsRepository#updateIfVersion}, not by JPA {@code @Version}, so that the
 * value the client sends in If-Match is compared atomically in the database.
 */
@Entity
@Table(name = "device_settings")
public class SettingsEntity {

    @Id
    @Column(name = "device_id", nullable = false)
    private UUID deviceId;

    @Column(name = "version", nullable = false)
    private long version;

    /** Canonical JSON of a validated {@link SettingsDocument}. */
    @Column(name = "document", nullable = false, length = 16384)
    private String document;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    protected SettingsEntity() {
    }

    SettingsEntity(UUID deviceId, long version, String document, Instant updatedAt) {
        this.deviceId = deviceId;
        this.version = version;
        this.document = document;
        this.updatedAt = updatedAt;
    }

    public UUID getDeviceId() {
        return deviceId;
    }

    public long getVersion() {
        return version;
    }

    public String getDocument() {
        return document;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }
}
