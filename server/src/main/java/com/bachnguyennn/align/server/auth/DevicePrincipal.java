package com.bachnguyennn.align.server.auth;

import java.util.UUID;

/** The authenticated device. Every data access is scoped to {@link #deviceId()}. */
public record DevicePrincipal(UUID deviceId) {

    @Override
    public String toString() {
        return "DevicePrincipal[" + deviceId + "]";
    }
}
