package com.bachnguyennn.align.server;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.Consumer;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;

class EventApiTest extends ApiTestSupport {

    private UUID newSession(Device device) throws Exception {
        UUID id = UUID.randomUUID();
        putSession(device, id, session()).andExpect(status().isCreated());
        return id;
    }

    @Test
    void batchUpsertIsIdempotentPerEvent() throws Exception {
        Device device = register();
        UUID sessionId = newSession(device);
        UUID first = UUID.randomUUID();
        UUID second = UUID.randomUUID();
        Map<String, Object> e1 = event(first, "2026-03-02T08:05:00Z", "2026-03-02T08:05:45Z");
        Map<String, Object> e2 = event(second, "2026-03-02T08:10:00Z", "2026-03-02T08:11:00Z");
        e2.put("deviationType", "left");
        e2.put("durationSeconds", 60.0);
        e2.put("reminderTriggered", false);

        putEvents(device, sessionId, batch(List.of(e2, e1)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.created").value(2))
                .andExpect(jsonPath("$.updated").value(0))
                .andExpect(jsonPath("$.unchanged").value(0));

        // Retry of the same batch: nothing changes.
        putEvents(device, sessionId, batch(List.of(e1, e2)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.created").value(0))
                .andExpect(jsonPath("$.unchanged").value(2));

        // One changed, one new, one unchanged. Events not in the batch are kept.
        Map<String, Object> e1Changed = new java.util.LinkedHashMap<>(e1);
        e1Changed.put("peakDeviationDegrees", 30.0);
        UUID third = UUID.randomUUID();
        putEvents(device, sessionId, batch(List.of(e1Changed, event(third, "2026-03-02T08:20:00Z", "2026-03-02T08:20:45Z"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.created").value(1))
                .andExpect(jsonPath("$.updated").value(1))
                .andExpect(jsonPath("$.unchanged").value(0));

        getAs(device, "/api/v1/sessions/{id}", sessionId)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.events.length()").value(3))
                // Ordered by startedAt.
                .andExpect(jsonPath("$.events[0].id").value(first.toString()))
                .andExpect(jsonPath("$.events[0].peakDeviationDegrees").value(30.0))
                .andExpect(jsonPath("$.events[0].deviationType").value("forward"))
                .andExpect(jsonPath("$.events[0].reminderTriggered").value(true))
                .andExpect(jsonPath("$.events[1].id").value(second.toString()))
                .andExpect(jsonPath("$.events[1].deviationType").value("left"))
                .andExpect(jsonPath("$.events[1].durationSeconds").value(60.0))
                .andExpect(jsonPath("$.events[1].reminderTriggered").value(false))
                .andExpect(jsonPath("$.events[2].id").value(third.toString()));
    }

    @Test
    void changedEventsMarkTheSessionUpdated() throws Exception {
        Device device = register();
        UUID sessionId = newSession(device);
        Instant before = Instant.parse(body(getAs(device, "/api/v1/sessions/{id}", sessionId)).get("updatedAt").asText());
        Thread.sleep(5);
        putEvents(device, sessionId, batch(List.of(event(UUID.randomUUID())))).andExpect(status().isOk());
        JsonNode after = body(getAs(device, "/api/v1/sessions/{id}", sessionId));
        assertThat(Instant.parse(after.get("updatedAt").asText())).isAfter(before);
    }

    @Test
    void eventsForUnknownSessionAre404() throws Exception {
        Device device = register();
        putEvents(device, UUID.randomUUID(), batch(List.of(event(UUID.randomUUID()))))
                .andExpect(problem(404, "not-found"));
    }

    @Test
    void eventIdReusedForAnotherSessionOfTheSameDeviceIs409() throws Exception {
        Device device = register();
        UUID a = newSession(device);
        UUID b = newSession(device);
        UUID eventId = UUID.randomUUID();
        putEvents(device, a, batch(List.of(event(eventId)))).andExpect(status().isOk());
        putEvents(device, b, batch(List.of(event(eventId)))).andExpect(problem(409, "conflict"));
        getAs(device, "/api/v1/sessions/{id}", b).andExpect(jsonPath("$.events.length()").value(0));
    }

    @Test
    void batchLimitIs500() throws Exception {
        Device device = register();
        UUID sessionId = newSession(device);
        List<Map<String, Object>> events = new ArrayList<>();
        for (int i = 0; i < 501; i++) {
            events.add(event(UUID.randomUUID()));
        }
        putEvents(device, sessionId, batch(events))
                .andExpect(problem(422, "validation-failed"))
                .andExpect(jsonPath("$.errors[0].field").value("events"));
        putEvents(device, sessionId, batch(events.subList(0, 500)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.created").value(500));
    }

    @Test
    void emptyBatchIs422() throws Exception {
        Device device = register();
        putEvents(device, newSession(device), batch(List.of())).andExpect(problem(422, "validation-failed"));
    }

    @Test
    void repeatedIdInOneBatchIs422() throws Exception {
        Device device = register();
        UUID id = UUID.randomUUID();
        putEvents(device, newSession(device), batch(List.of(event(id), event(id))))
                .andExpect(problem(422, "validation-failed"))
                .andExpect(jsonPath("$.errors[0].field").value("events[1].id"));
    }

    static Stream<Arguments> invalidEvents() {
        return Stream.of(
                invalid("unknown direction", "events[0].deviationType", e -> e.put("deviationType", "up")),
                invalid("negative duration", "events[0].durationSeconds", e -> e.put("durationSeconds", -1.0)),
                invalid("duration over a day", "events[0].durationSeconds", e -> e.put("durationSeconds", 86_401.0)),
                invalid("peak over 180", "events[0].peakDeviationDegrees", e -> e.put("peakDeviationDegrees", 180.5)),
                invalid("negative peak", "events[0].peakDeviationDegrees", e -> e.put("peakDeviationDegrees", -0.1)),
                invalid("ended before started", "events[0].endedAt", e -> e.put("endedAt", "2026-03-02T08:04:59Z")),
                invalid("before 2020", "events[0].startedAt", e -> e.put("startedAt", "2019-01-01T00:00:00Z")),
                invalid("missing id", "events[0].id", e -> e.remove("id")),
                invalid("missing reminderTriggered", "events[0].reminderTriggered", e -> e.remove("reminderTriggered")));
    }

    private static Arguments invalid(String name, String field, Consumer<Map<String, Object>> change) {
        Map<String, Object> e = event(UUID.randomUUID());
        change.accept(e);
        return Arguments.of(name, field, e);
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("invalidEvents")
    void invalidEventIs422AndNothingIsStored(String name, String field, Map<String, Object> bad) throws Exception {
        Device device = register();
        UUID sessionId = newSession(device);
        putEvents(device, sessionId, batch(List.of(bad, event(UUID.randomUUID()))))
                .andExpect(problem(422, "validation-failed"))
                .andExpect(jsonPath("$.errors[*].field").value(org.hamcrest.Matchers.hasItem(field)));
        getAs(device, "/api/v1/sessions/{id}", sessionId).andExpect(jsonPath("$.events.length()").value(0));
    }

    @Test
    void rawMotionFieldsAreRejected() throws Exception {
        Device device = register();
        Map<String, Object> e = event(UUID.randomUUID());
        e.put("samples", List.of(Map.of("timestamp", 1.0, "gravity", List.of(0, 0, -1))));
        putEvents(device, newSession(device), batch(List.of(e))).andExpect(problem(400, "malformed-request"));
    }
}
