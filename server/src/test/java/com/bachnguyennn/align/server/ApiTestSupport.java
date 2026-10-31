package com.bachnguyennn.align.server;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.hamcrest.Matchers;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.ResultMatcher;

/**
 * Shared setup: the full application with MockMvc (all servlet filters, Spring Security, Flyway
 * migrations on the test database). Each test registers fresh devices, so tests never share data.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
public abstract class ApiTestSupport {

    @Autowired
    protected MockMvc mvc;

    @Autowired
    protected ObjectMapper json;

    /** A registered test device. */
    protected record Device(UUID id, String token) {
        public String bearer() {
            return "Bearer " + token;
        }
    }

    protected Device register() throws Exception {
        String body = mvc.perform(post("/api/v1/devices"))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        JsonNode node = json.readTree(body);
        return new Device(UUID.fromString(node.get("deviceId").asText()), node.get("token").asText());
    }

    /** A valid session body (ended, 20 minutes monitored). */
    protected static Map<String, Object> session(String startedAt, String endedAt) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("startedAt", startedAt);
        body.put("endedAt", endedAt);
        body.put("monitoredDurationSeconds", 1200.0);
        body.put("withinThresholdSeconds", 1080.0);
        body.put("sustainedDeviationSeconds", 120.0);
        body.put("reminderCount", 2);
        body.put("calibrationVersion", 3);
        body.put("sensorAvailabilityStatus", "real");
        return body;
    }

    protected static Map<String, Object> session() {
        return session("2026-03-02T08:00:00Z", "2026-03-02T08:30:00Z");
    }

    protected static Map<String, Object> event(UUID id, String startedAt, String endedAt) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("id", id.toString());
        body.put("startedAt", startedAt);
        body.put("endedAt", endedAt);
        body.put("deviationType", "forward");
        body.put("durationSeconds", 45.0);
        body.put("peakDeviationDegrees", 22.5);
        body.put("reminderTriggered", true);
        return body;
    }

    protected static Map<String, Object> event(UUID id) {
        return event(id, "2026-03-02T08:05:00Z", "2026-03-02T08:05:45Z");
    }

    protected static Map<String, Object> batch(List<Map<String, Object>> events) {
        return Map.of("events", events);
    }

    protected ResultActions putSession(Device device, UUID id, Object body) throws Exception {
        return mvc.perform(put("/api/v1/sessions/{id}", id)
                .header(HttpHeaders.AUTHORIZATION, device.bearer())
                .contentType(MediaType.APPLICATION_JSON)
                .content(json.writeValueAsString(body)));
    }

    protected ResultActions putEvents(Device device, UUID sessionId, Object body) throws Exception {
        return mvc.perform(put("/api/v1/sessions/{id}/events", sessionId)
                .header(HttpHeaders.AUTHORIZATION, device.bearer())
                .contentType(MediaType.APPLICATION_JSON)
                .content(json.writeValueAsString(body)));
    }

    protected ResultActions getAs(Device device, String uri, Object... vars) throws Exception {
        return mvc.perform(get(uri, vars).header(HttpHeaders.AUTHORIZATION, device.bearer()));
    }

    protected JsonNode body(ResultActions result) throws Exception {
        return json.readTree(result.andReturn().getResponse().getContentAsString());
    }

    /** Asserts an RFC 9457 problem response with the given status and type slug. */
    protected static ResultMatcher problem(int status, String typeSlug) {
        List<ResultMatcher> matchers = List.of(
                status().is(status),
                content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON),
                jsonPath("$.status").value(status),
                jsonPath("$.type").value(Matchers.endsWith("#" + typeSlug)),
                jsonPath("$.title").isString());
        return result -> {
            for (ResultMatcher matcher : matchers) {
                matcher.match(result);
            }
        };
    }
}
