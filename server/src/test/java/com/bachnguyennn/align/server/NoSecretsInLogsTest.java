package com.bachnguyennn.align.server;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;

import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;

/** Tokens and payload contents must never reach the log, including on error paths. */
@ExtendWith(OutputCaptureExtension.class)
class NoSecretsInLogsTest extends ApiTestSupport {

    @Test
    void tokensAndPayloadValuesAreNotLogged(CapturedOutput output) throws Exception {
        Device device = register();
        UUID sessionId = UUID.randomUUID();
        Map<String, Object> body = session();
        body.put("monitoredDurationSeconds", 1234.5678);
        putSession(device, sessionId, body);
        Map<String, Object> event = event(UUID.randomUUID());
        event.put("peakDeviationDegrees", 87.654321);
        putEvents(device, sessionId, batch(List.of(event)));

        // Error paths: invalid values, unknown fields, malformed JSON, conflicts, bad tokens.
        Map<String, Object> invalid = session();
        invalid.put("sensorAvailabilityStatus", "payload-marker-qwerty");
        putSession(device, UUID.randomUUID(), invalid);
        Map<String, Object> unknown = session();
        unknown.put("note", "payload-marker-asdfgh");
        putSession(device, UUID.randomUUID(), unknown);
        mvc.perform(put("/api/v1/sessions/{id}", UUID.randomUUID()).header(HttpHeaders.AUTHORIZATION, device.bearer())
                .contentType(MediaType.APPLICATION_JSON).content("{\"startedAt\": payload-marker-zxcvbn"));
        UUID other = UUID.randomUUID();
        putSession(device, other, session());
        putEvents(device, other, batch(List.of(event)));
        mvc.perform(put("/api/v1/settings").header(HttpHeaders.AUTHORIZATION, device.bearer())
                .header(HttpHeaders.IF_MATCH, "\"5\"").contentType(MediaType.APPLICATION_JSON)
                .content("{\"settings\":{\"soundEnabled\":false}}"));
        String fakeToken = "A".repeat(43);
        getAs(new Device(device.id(), fakeToken), "/api/v1/sessions");

        assertThat(output.getAll())
                .doesNotContain(device.token())
                .doesNotContain(fakeToken)
                .doesNotContain("1234.5678")
                .doesNotContain("87.654321")
                .doesNotContain("payload-marker");
    }
}
