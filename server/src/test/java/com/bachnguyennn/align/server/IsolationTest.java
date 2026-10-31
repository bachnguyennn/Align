package com.bachnguyennn.align.server;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;

/** A device can only ever see or change its own data. */
class IsolationTest extends ApiTestSupport {

    @Test
    void anotherDeviceCannotReadOrExtendASession() throws Exception {
        Device owner = register();
        Device intruder = register();
        UUID sessionId = UUID.randomUUID();
        putSession(owner, sessionId, session()).andExpect(status().isCreated());
        putEvents(owner, sessionId, batch(List.of(event(UUID.randomUUID())))).andExpect(status().isOk());

        // Same 404 as for an id that does not exist at all.
        getAs(intruder, "/api/v1/sessions/{id}", sessionId).andExpect(problem(404, "not-found"));
        getAs(intruder, "/api/v1/sessions/{id}", UUID.randomUUID()).andExpect(problem(404, "not-found"));
        putEvents(intruder, sessionId, batch(List.of(event(UUID.randomUUID())))).andExpect(problem(404, "not-found"));

        getAs(intruder, "/api/v1/sessions").andExpect(jsonPath("$.items.length()").value(0));
        getAs(intruder, "/api/v1/analytics/summary?from=2026-03-02&to=2026-03-02&tz=UTC")
                .andExpect(jsonPath("$.days[0].totalMonitoredMinutes").value(0.0));

        getAs(owner, "/api/v1/sessions/{id}", sessionId)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.events.length()").value(1));
    }

    @Test
    void ids_are_scoped_per_device_so_reusing_one_never_touches_the_owner() throws Exception {
        Device owner = register();
        Device other = register();
        UUID sessionId = UUID.randomUUID();
        UUID eventId = UUID.randomUUID();
        putSession(owner, sessionId, session()).andExpect(status().isCreated());
        putEvents(owner, sessionId, batch(List.of(event(eventId)))).andExpect(status().isOk());

        // The other device uploading the same UUIDs gets its own, independent rows: 201 exactly as
        // for a fresh UUID, so the response reveals nothing about the owner's data.
        Map<String, Object> different = session();
        different.put("reminderCount", 9);
        putSession(other, sessionId, different).andExpect(status().isCreated())
                .andExpect(jsonPath("$.reminderCount").value(9));
        Map<String, Object> otherEvent = event(eventId);
        otherEvent.put("deviationType", "right");
        putEvents(other, sessionId, batch(List.of(otherEvent)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.created").value(1));

        getAs(owner, "/api/v1/sessions/{id}", sessionId)
                .andExpect(jsonPath("$.reminderCount").value(2))
                .andExpect(jsonPath("$.events.length()").value(1))
                .andExpect(jsonPath("$.events[0].deviationType").value("forward"));
        getAs(other, "/api/v1/sessions/{id}", sessionId)
                .andExpect(jsonPath("$.reminderCount").value(9))
                .andExpect(jsonPath("$.events[0].deviationType").value("right"));
    }

    @Test
    void settingsAreSeparatePerDevice() throws Exception {
        Device a = register();
        Device b = register();
        mvc.perform(put("/api/v1/settings").header(HttpHeaders.AUTHORIZATION, a.bearer())
                        .header(HttpHeaders.IF_MATCH, "\"0\"").contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of("settings", Map.of("hapticsEnabled", false)))))
                .andExpect(status().isOk());
        mvc.perform(get("/api/v1/settings").header(HttpHeaders.AUTHORIZATION, b.bearer()))
                .andExpect(jsonPath("$.version").value(0))
                .andExpect(jsonPath("$.settings.hapticsEnabled").doesNotExist());
    }

    @Test
    void erasingOneDeviceKeepsTheOthers() throws Exception {
        Device a = register();
        Device b = register();
        UUID id = UUID.randomUUID();
        putSession(a, id, session()).andExpect(status().isCreated());
        putSession(b, id, session()).andExpect(status().isCreated());
        mvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete("/api/v1/devices/me")
                .header(HttpHeaders.AUTHORIZATION, b.bearer())).andExpect(status().isNoContent());
        getAs(a, "/api/v1/sessions/{id}", id).andExpect(status().isOk());
    }
}
