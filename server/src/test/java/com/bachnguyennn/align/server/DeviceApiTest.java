package com.bachnguyennn.align.server;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.bachnguyennn.align.server.auth.TokenService;
import com.bachnguyennn.align.server.device.DeviceEntity;
import com.bachnguyennn.align.server.device.DeviceRepository;
import com.bachnguyennn.align.server.session.PostureEventRepository;
import com.bachnguyennn.align.server.session.SessionRepository;
import com.bachnguyennn.align.server.settings.SettingsRepository;
import com.fasterxml.jackson.databind.JsonNode;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;

class DeviceApiTest extends ApiTestSupport {

    @Autowired
    DeviceRepository devices;
    @Autowired
    SessionRepository sessions;
    @Autowired
    PostureEventRepository events;
    @Autowired
    SettingsRepository settings;
    @Autowired
    TokenService tokens;

    @Test
    void registerReturnsDeviceIdAndOneTimeToken() throws Exception {
        JsonNode node = body(mvc.perform(post("/api/v1/devices"))
                .andExpect(status().isCreated())
                .andExpect(header().string(HttpHeaders.LOCATION, "/api/v1/devices/me"))
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, org.hamcrest.Matchers.containsString("no-store")))
                .andExpect(jsonPath("$.deviceId").isString())
                .andExpect(jsonPath("$.createdAt").isString()));
        String token = node.get("token").asText();
        assertThat(token).matches("[A-Za-z0-9_-]{43}");

        // Only the SHA-256 hash is stored, never the token.
        DeviceEntity stored = devices.findById(UUID.fromString(node.get("deviceId").asText())).orElseThrow();
        assertThat(stored.getTokenSha256()).isEqualTo(tokens.hash(token)).isNotEqualTo(token).hasSize(64);
    }

    @Test
    void eachRegistrationIsANewDeviceWithADifferentToken() throws Exception {
        Device a = register();
        Device b = register();
        assertThat(a.id()).isNotEqualTo(b.id());
        assertThat(a.token()).isNotEqualTo(b.token());
    }

    @Test
    void registrationIgnoresAnInvalidAuthorizationHeader() throws Exception {
        mvc.perform(post("/api/v1/devices").header(HttpHeaders.AUTHORIZATION, "Bearer nonsense"))
                .andExpect(status().isCreated());
    }

    @Test
    void meReturnsTheCallingDevice() throws Exception {
        Device device = register();
        getAs(device, "/api/v1/devices/me")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.deviceId").value(device.id().toString()))
                .andExpect(jsonPath("$.token").doesNotExist());
    }

    @Test
    void eraseRemovesEverythingAndRevokesTheToken() throws Exception {
        Device device = register();
        Device other = register();
        UUID sessionId = UUID.randomUUID();
        putSession(device, sessionId, session()).andExpect(status().isCreated());
        putEvents(device, sessionId, batch(List.of(event(UUID.randomUUID()), event(UUID.randomUUID()))))
                .andExpect(status().isOk());
        mvc.perform(put("/api/v1/settings").header(HttpHeaders.AUTHORIZATION, device.bearer())
                        .header(HttpHeaders.IF_MATCH, "\"0\"")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of("settings", Map.of("soundEnabled", false)))))
                .andExpect(status().isOk());
        UUID otherSession = UUID.randomUUID();
        putSession(other, otherSession, session()).andExpect(status().isCreated());
        putEvents(other, otherSession, batch(List.of(event(UUID.randomUUID())))).andExpect(status().isOk());

        mvc.perform(delete("/api/v1/devices/me").header(HttpHeaders.AUTHORIZATION, device.bearer()))
                .andExpect(status().isNoContent());

        assertThat(devices.findById(device.id())).isEmpty();
        assertThat(sessions.findAll()).noneMatch(s -> s.getDeviceId().equals(device.id()));
        assertThat(events.findAll()).noneMatch(e -> e.getDeviceId().equals(device.id()));
        assertThat(settings.findById(device.id())).isEmpty();
        assertThat(events.findAll()).anyMatch(e -> e.getDeviceId().equals(other.id()));
        getAs(device, "/api/v1/sessions/{id}", sessionId).andExpect(problem(401, "unauthorized"));
        mvc.perform(delete("/api/v1/devices/me").header(HttpHeaders.AUTHORIZATION, device.bearer()))
                .andExpect(problem(401, "unauthorized"));

        // The other device is untouched.
        getAs(other, "/api/v1/sessions/{id}", otherSession)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.events.length()").value(1));
    }
}
