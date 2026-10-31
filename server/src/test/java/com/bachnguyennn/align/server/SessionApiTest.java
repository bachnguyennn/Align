package com.bachnguyennn.align.server;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Map;
import java.util.UUID;
import java.util.function.Consumer;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;

class SessionApiTest extends ApiTestSupport {

    @Test
    void createThenIdempotentRepeatThenUpdate() throws Exception {
        Device device = register();
        UUID id = UUID.randomUUID();

        JsonNode created = body(putSession(device, id, session())
                .andExpect(status().isCreated())
                .andExpect(header().string(HttpHeaders.LOCATION, "/api/v1/sessions/" + id))
                .andExpect(jsonPath("$.id").value(id.toString()))
                .andExpect(jsonPath("$.startedAt").value("2026-03-02T08:00:00Z"))
                .andExpect(jsonPath("$.endedAt").value("2026-03-02T08:30:00Z"))
                .andExpect(jsonPath("$.monitoredDurationSeconds").value(1200.0))
                .andExpect(jsonPath("$.withinThresholdSeconds").value(1080.0))
                .andExpect(jsonPath("$.sustainedDeviationSeconds").value(120.0))
                .andExpect(jsonPath("$.reminderCount").value(2))
                .andExpect(jsonPath("$.calibrationVersion").value(3))
                .andExpect(jsonPath("$.sensorAvailabilityStatus").value("real"))
                .andExpect(jsonPath("$.events").doesNotExist()));

        // Same id + same body: 200, nothing changes (updatedAt included).
        JsonNode repeated = body(putSession(device, id, session()).andExpect(status().isOk()));
        assertThat(repeated).isEqualTo(created);

        // Same id + new body: 200 with the new values and a later updatedAt.
        Map<String, Object> changed = session();
        changed.put("reminderCount", 3);
        JsonNode updated = body(putSession(device, id, changed)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.reminderCount").value(3)));
        assertThat(updated.get("createdAt")).isEqualTo(created.get("createdAt"));
        assertThat(Instant.parse(updated.get("updatedAt").asText()))
                .isAfterOrEqualTo(Instant.parse(created.get("updatedAt").asText()));

        getAs(device, "/api/v1/sessions/{id}", id)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.reminderCount").value(3))
                .andExpect(jsonPath("$.events.length()").value(0));
    }

    @Test
    void openSessionCanBeUploadedAndClosedLater() throws Exception {
        Device device = register();
        UUID id = UUID.randomUUID();
        Map<String, Object> open = session("2026-03-02T08:00:00Z", null);
        putSession(device, id, open)
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.endedAt").isEmpty());
        putSession(device, id, session()).andExpect(status().isOk())
                .andExpect(jsonPath("$.endedAt").value("2026-03-02T08:30:00Z"));
    }

    @Test
    void timestampsKeepMicrosecondsAndReuploadWithNanosIsUnchanged() throws Exception {
        Device device = register();
        UUID id = UUID.randomUUID();
        Map<String, Object> body = session("2026-03-02T08:00:00.123456789Z", "2026-03-02T10:30:00+02:00");
        JsonNode first = body(putSession(device, id, body)
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.startedAt").value("2026-03-02T08:00:00.123456Z"))
                .andExpect(jsonPath("$.endedAt").value("2026-03-02T08:30:00Z")));
        Map<String, Object> again = session("2026-03-02T08:00:00.123456Z", "2026-03-02T08:30:00Z");
        assertThat(body(putSession(device, id, again).andExpect(status().isOk()))).isEqualTo(first);
    }

    @Test
    void bodyIdMustMatchPath() throws Exception {
        Device device = register();
        UUID id = UUID.randomUUID();
        Map<String, Object> body = session();
        body.put("id", id.toString());
        putSession(device, id, body).andExpect(status().isCreated());
        body.put("id", UUID.randomUUID().toString());
        putSession(device, id, body)
                .andExpect(problem(422, "validation-failed"))
                .andExpect(jsonPath("$.errors[0].field").value("id"));
    }

    @Test
    void unknownSessionIs404() throws Exception {
        Device device = register();
        getAs(device, "/api/v1/sessions/{id}", UUID.randomUUID()).andExpect(problem(404, "not-found"));
    }

    static Stream<Arguments> invalidSessions() {
        String future = Instant.now().plus(2, ChronoUnit.DAYS).truncatedTo(ChronoUnit.SECONDS).toString();
        return Stream.of(
                invalid("negative monitored", "monitoredDurationSeconds", b -> b.put("monitoredDurationSeconds", -1.0)),
                invalid("negative within", "withinThresholdSeconds", b -> b.put("withinThresholdSeconds", -0.5)),
                invalid("huge sustained", "sustainedDeviationSeconds", b -> b.put("sustainedDeviationSeconds", 1e9)),
                invalid("infinite via overflow", "monitoredDurationSeconds", b -> b.put("monitoredDurationSeconds", Double.POSITIVE_INFINITY)),
                invalid("negative reminders", "reminderCount", b -> b.put("reminderCount", -1)),
                invalid("too many reminders", "reminderCount", b -> b.put("reminderCount", 100_001)),
                invalid("negative calibration", "calibrationVersion", b -> b.put("calibrationVersion", -1)),
                invalid("unknown status", "sensorAvailabilityStatus", b -> b.put("sensorAvailabilityStatus", "airpods")),
                invalid("missing startedAt", "startedAt", b -> b.remove("startedAt")),
                invalid("missing reminderCount", "reminderCount", b -> b.remove("reminderCount")),
                invalid("ended before started", "endedAt", b -> b.put("endedAt", "2026-03-02T07:59:59Z")),
                invalid("longer than 7 days", "endedAt", b -> b.put("endedAt", "2026-03-10T08:00:00Z")),
                invalid("before 2020", "startedAt", b -> b.put("startedAt", "2019-12-31T23:59:59Z")),
                invalid("in the future", "startedAt", b -> {
                    b.put("startedAt", future);
                    b.put("endedAt", null);
                }),
                invalid("parts exceed monitored", "monitoredDurationSeconds", b -> b.put("withinThresholdSeconds", 1100.0)));
    }

    private static Arguments invalid(String name, String field, Consumer<Map<String, Object>> change) {
        Map<String, Object> body = session();
        change.accept(body);
        return Arguments.of(name, field, body);
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("invalidSessions")
    void invalidSessionIs422WithField(String name, String field, Map<String, Object> body) throws Exception {
        Device device = register();
        UUID id = UUID.randomUUID();
        // Infinity is not JSON; send 1e400, which a lenient parser would read as Infinity.
        String raw = json.writeValueAsString(body).replace("\"Infinity\"", "1e400");
        mvc.perform(put("/api/v1/sessions/{id}", id).header(HttpHeaders.AUTHORIZATION, device.bearer())
                        .contentType(MediaType.APPLICATION_JSON).content(raw))
                .andExpect(problem(422, "validation-failed"))
                .andExpect(jsonPath("$.errors[*].field").value(org.hamcrest.Matchers.hasItem(field)));
        getAs(device, "/api/v1/sessions/{id}", id).andExpect(status().isNotFound());
    }

    static Stream<Arguments> malformedBodies() {
        return Stream.of(
                Arguments.of("not JSON", "{"),
                Arguments.of("empty body", ""),
                Arguments.of("array instead of object", "[]"),
                Arguments.of("unknown field", json(b -> b.put("rawSamples", "[]"))),
                Arguments.of("string for a number", json(b -> b.put("reminderCount", "2"))),
                Arguments.of("fraction for an integer", json(b -> b.put("reminderCount", 2.5))),
                Arguments.of("number for a string", json(b -> b.put("sensorAvailabilityStatus", 1))),
                Arguments.of("not a timestamp", json(b -> b.put("startedAt", "yesterday"))),
                Arguments.of("NaN", json(b -> b.put("monitoredDurationSeconds", "NaN")).replace("\"NaN\"", "NaN")),
                Arguments.of("duplicate key", "{\"reminderCount\":1,\"reminderCount\":2}"),
                Arguments.of("trailing tokens", json(b -> { }) + "{}"));
    }

    private static String json(Consumer<Map<String, Object>> change) {
        Map<String, Object> body = session();
        change.accept(body);
        try {
            return new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(body);
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("malformedBodies")
    void malformedBodyIs400(String name, String raw) throws Exception {
        Device device = register();
        mvc.perform(put("/api/v1/sessions/{id}", UUID.randomUUID()).header(HttpHeaders.AUTHORIZATION, device.bearer())
                        .contentType(MediaType.APPLICATION_JSON).content(raw))
                .andExpect(problem(400, "malformed-request"));
    }

    @Test
    void validationErrorsNeverEchoValues() throws Exception {
        Device device = register();
        Map<String, Object> body = session();
        body.put("sensorAvailabilityStatus", "secret-value-xyz");
        String response = putSession(device, UUID.randomUUID(), body)
                .andExpect(problem(422, "validation-failed"))
                .andReturn().getResponse().getContentAsString();
        assertThat(response).doesNotContain("secret-value-xyz");

        Map<String, Object> unknown = session();
        unknown.put("secretFieldValue", "another-secret-abc");
        String response2 = putSession(device, UUID.randomUUID(), unknown)
                .andExpect(problem(400, "malformed-request"))
                .andExpect(jsonPath("$.detail").value("Unknown field 'secretFieldValue'."))
                .andReturn().getResponse().getContentAsString();
        assertThat(response2).doesNotContain("another-secret-abc");
    }

    @Test
    void badPathIdIs400() throws Exception {
        Device device = register();
        mvc.perform(put("/api/v1/sessions/not-a-uuid").header(HttpHeaders.AUTHORIZATION, device.bearer())
                        .contentType(MediaType.APPLICATION_JSON).content(json.writeValueAsString(session())))
                .andExpect(problem(400, "invalid-parameter"));
    }

    @Test
    void wrongContentTypeIs415() throws Exception {
        Device device = register();
        mvc.perform(put("/api/v1/sessions/{id}", UUID.randomUUID()).header(HttpHeaders.AUTHORIZATION, device.bearer())
                        .contentType(MediaType.TEXT_PLAIN).content("hello"))
                .andExpect(problem(415, "unsupported-media-type"));
    }
}
