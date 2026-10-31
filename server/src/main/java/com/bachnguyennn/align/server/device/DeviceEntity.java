package com.bachnguyennn.align.server.device;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

/** An anonymous device registration. No name, account, hardware identifier or IP is stored. */
@Entity
@Table(name = "device")
public class DeviceEntity {

    @Id
    @Column(name = "id", nullable = false)
    private UUID id;

    /** Lower-case hex SHA-256 of the bearer token. */
    @Column(name = "token_sha256", nullable = false, length = 64)
    private String tokenSha256;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    protected DeviceEntity() {
    }

    public DeviceEntity(UUID id, String tokenSha256, Instant createdAt) {
        this.id = id;
        this.tokenSha256 = tokenSha256;
        this.createdAt = createdAt;
    }

    public UUID getId() {
        return id;
    }

    public String getTokenSha256() {
        return tokenSha256;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
