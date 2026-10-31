package com.bachnguyennn.align.server.auth;

import com.bachnguyennn.align.server.web.ProblemType;
import com.bachnguyennn.align.server.web.Problems;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.http.HttpHeaders;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.web.AuthenticationEntryPoint;

/** 401 as problem+json with an RFC 6750 {@code WWW-Authenticate} challenge. */
public class ProblemAuthenticationEntryPoint implements AuthenticationEntryPoint {

    private final Problems problems;

    public ProblemAuthenticationEntryPoint(Problems problems) {
        this.problems = problems;
    }

    @Override
    public void commence(HttpServletRequest request, HttpServletResponse response,
            AuthenticationException authException) throws IOException {
        boolean invalid = request.getAttribute(BearerTokenAuthenticationFilter.INVALID_TOKEN_ATTRIBUTE) != null;
        response.setHeader(HttpHeaders.WWW_AUTHENTICATE,
                invalid ? "Bearer error=\"invalid_token\"" : "Bearer");
        problems.write(request, response, ProblemType.UNAUTHORIZED, invalid
                ? "The bearer token is not valid. Register again with POST /api/v1/devices if it was erased."
                : "Send Authorization: Bearer <token>.");
    }
}
