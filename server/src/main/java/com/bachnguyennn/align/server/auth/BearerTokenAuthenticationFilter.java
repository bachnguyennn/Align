package com.bachnguyennn.align.server.auth;

import com.bachnguyennn.align.server.device.DeviceRepository;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.http.HttpHeaders;
import org.springframework.security.core.context.SecurityContext;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Authenticates {@code Authorization: Bearer <token>}. The token is hashed and looked up by hash;
 * the stored hash is then compared in constant time. A missing or invalid token leaves the
 * request unauthenticated; protected endpoints then answer 401 via {@link ProblemAuthenticationEntryPoint}.
 * The token is never logged or kept beyond this method.
 */
public class BearerTokenAuthenticationFilter extends OncePerRequestFilter {

    /** Request attribute set when an Authorization header was present but not accepted. */
    public static final String INVALID_TOKEN_ATTRIBUTE = BearerTokenAuthenticationFilter.class.getName() + ".invalid";

    private static final String BEARER_PREFIX = "Bearer ";

    private final TokenService tokens;
    private final DeviceRepository devices;

    public BearerTokenAuthenticationFilter(TokenService tokens, DeviceRepository devices) {
        this.tokens = tokens;
        this.devices = devices;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        String header = request.getHeader(HttpHeaders.AUTHORIZATION);
        if (header != null) {
            DevicePrincipal principal = authenticate(header);
            if (principal != null) {
                SecurityContext context = SecurityContextHolder.createEmptyContext();
                context.setAuthentication(new DeviceAuthentication(principal));
                SecurityContextHolder.setContext(context);
            } else {
                request.setAttribute(INVALID_TOKEN_ATTRIBUTE, Boolean.TRUE);
            }
        }
        chain.doFilter(request, response);
    }

    private DevicePrincipal authenticate(String header) {
        if (header.length() <= BEARER_PREFIX.length()
                || !header.regionMatches(true, 0, BEARER_PREFIX, 0, BEARER_PREFIX.length())) {
            return null;
        }
        String token = header.substring(BEARER_PREFIX.length()).trim();
        if (!tokens.isWellFormed(token)) {
            return null;
        }
        String hash = tokens.hash(token);
        return devices.findByTokenSha256(hash)
                .filter(device -> tokens.hashesEqual(device.getTokenSha256(), hash))
                .map(device -> new DevicePrincipal(device.getId()))
                .orElse(null);
    }
}
