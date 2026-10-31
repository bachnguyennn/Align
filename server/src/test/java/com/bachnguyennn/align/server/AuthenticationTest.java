package com.bachnguyennn.align.server;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.request;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.bachnguyennn.align.server.auth.TokenService;
import java.util.UUID;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

class AuthenticationTest extends ApiTestSupport {

    @Autowired
    TokenService tokens;

    static Stream<Arguments> protectedEndpoints() {
        UUID id = UUID.randomUUID();
        return Stream.of(
                Arguments.of(HttpMethod.GET, "/api/v1/devices/me"),
                Arguments.of(HttpMethod.DELETE, "/api/v1/devices/me"),
                Arguments.of(HttpMethod.PUT, "/api/v1/sessions/" + id),
                Arguments.of(HttpMethod.GET, "/api/v1/sessions/" + id),
                Arguments.of(HttpMethod.GET, "/api/v1/sessions"),
                Arguments.of(HttpMethod.PUT, "/api/v1/sessions/" + id + "/events"),
                Arguments.of(HttpMethod.GET, "/api/v1/analytics/summary?from=2026-03-01&to=2026-03-07&tz=UTC"),
                Arguments.of(HttpMethod.GET, "/api/v1/settings"),
                Arguments.of(HttpMethod.PUT, "/api/v1/settings"),
                Arguments.of(HttpMethod.GET, "/api/v1/env"),
                Arguments.of(HttpMethod.GET, "/no/such/path"));
    }

    private static MockHttpServletRequestBuilder call(HttpMethod method, String uri) {
        MockHttpServletRequestBuilder builder = request(method, uri);
        if (method == HttpMethod.PUT) {
            builder.contentType(MediaType.APPLICATION_JSON).content("{}");
        }
        return builder;
    }

    @ParameterizedTest(name = "{0} {1} without a token is 401")
    @MethodSource("protectedEndpoints")
    void missingTokenIs401(HttpMethod method, String uri) throws Exception {
        mvc.perform(call(method, uri))
                .andExpect(problem(401, "unauthorized"))
                .andExpect(header().string(HttpHeaders.WWW_AUTHENTICATE, "Bearer"));
    }

    @ParameterizedTest(name = "{0} {1} with an unknown token is 401")
    @MethodSource("protectedEndpoints")
    void unknownTokenIs401(HttpMethod method, String uri) throws Exception {
        mvc.perform(call(method, uri).header(HttpHeaders.AUTHORIZATION, "Bearer " + tokens.newToken()))
                .andExpect(problem(401, "unauthorized"))
                .andExpect(header().string(HttpHeaders.WWW_AUTHENTICATE, "Bearer error=\"invalid_token\""));
    }

    @ParameterizedTest(name = "Authorization: {0}")
    @ValueSource(strings = {
            "Bearer",
            "Bearer ",
            "Bearer short",
            "Bearer aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa=",
            "Bearer aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa+",
            "Basic dXNlcjpwYXNz",
            "Token aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"})
    void malformedAuthorizationIs401(String header) throws Exception {
        mvc.perform(get("/api/v1/sessions").header(HttpHeaders.AUTHORIZATION, header))
                .andExpect(problem(401, "unauthorized"));
    }

    @Test
    void tokenIsCaseSensitive() throws Exception {
        Device device = register();
        String flipped = flipCase(device.token());
        mvc.perform(get("/api/v1/devices/me").header(HttpHeaders.AUTHORIZATION, "Bearer " + flipped))
                .andExpect(problem(401, "unauthorized"));
        // The scheme name itself is case-insensitive (RFC 7235).
        mvc.perform(get("/api/v1/devices/me").header(HttpHeaders.AUTHORIZATION, "bearer " + device.token()))
                .andExpect(status().isOk());
    }

    @Test
    void healthIsPublicAndShowsNoDetails() throws Exception {
        mvc.perform(get("/api/v1/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"))
                .andExpect(jsonPath("$.components").doesNotExist())
                .andExpect(jsonPath("$.details").doesNotExist());
    }

    @Test
    void otherActuatorEndpointsAreNotExposed() throws Exception {
        Device device = register();
        for (String path : new String[] {"/api/v1/env", "/api/v1/beans", "/api/v1/metrics", "/api/v1/info",
                "/actuator", "/actuator/health"}) {
            getAs(device, path).andExpect(problem(404, "not-found"));
        }
    }

    @Test
    void unknownRouteWithTokenIs404Problem() throws Exception {
        Device device = register();
        getAs(device, "/api/v1/nothing-here").andExpect(problem(404, "not-found"));
    }

    @Test
    void wrongMethodIs405Problem() throws Exception {
        Device device = register();
        mvc.perform(request(HttpMethod.POST, "/api/v1/settings").header(HttpHeaders.AUTHORIZATION, device.bearer()))
                .andExpect(problem(405, "method-not-allowed"));
    }

    private static String flipCase(String token) {
        StringBuilder out = new StringBuilder();
        boolean flipped = false;
        for (char c : token.toCharArray()) {
            if (!flipped && Character.isLetter(c)) {
                out.append(Character.isUpperCase(c) ? Character.toLowerCase(c) : Character.toUpperCase(c));
                flipped = true;
            } else {
                out.append(c);
            }
        }
        return out.toString();
    }
}
