package com.bachnguyennn.align.server.auth;

import java.util.List;
import org.springframework.security.authentication.AbstractAuthenticationToken;

/** A request authenticated by a device bearer token. Holds no credentials after authentication. */
public final class DeviceAuthentication extends AbstractAuthenticationToken {

    private final DevicePrincipal principal;

    public DeviceAuthentication(DevicePrincipal principal) {
        super(List.of());
        this.principal = principal;
        setAuthenticated(true);
    }

    @Override
    public Object getCredentials() {
        return null;
    }

    @Override
    public DevicePrincipal getPrincipal() {
        return principal;
    }
}
