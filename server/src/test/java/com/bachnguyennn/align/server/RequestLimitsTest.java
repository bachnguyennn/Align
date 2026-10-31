package com.bachnguyennn.align.server;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;

class RequestLimitsTest extends ApiTestSupport {

    @Test
    void bodiesOverTheLimitAre413() throws Exception {
        Device device = register();
        byte[] big = new byte[524_289];
        java.util.Arrays.fill(big, (byte) ' ');
        mvc.perform(put("/api/v1/sessions/{id}", UUID.randomUUID()).header(HttpHeaders.AUTHORIZATION, device.bearer())
                        .contentType(MediaType.APPLICATION_JSON).content(big))
                .andExpect(problem(413, "payload-too-large"));
    }

    @Test
    void largestBatchFitsUnderTheLimit() throws Exception {
        Device device = register();
        UUID sessionId = UUID.randomUUID();
        putSession(device, sessionId, session()).andExpect(status().isCreated());
        List<Map<String, Object>> events = new ArrayList<>();
        for (int i = 0; i < 500; i++) {
            events.add(event(UUID.randomUUID()));
        }
        putEvents(device, sessionId, batch(events)).andExpect(status().isOk());
    }

    @Test
    void sessionEventLimitIs5000() throws Exception {
        Device device = register();
        UUID sessionId = UUID.randomUUID();
        putSession(device, sessionId, session()).andExpect(status().isCreated());
        for (int round = 0; round < 10; round++) {
            List<Map<String, Object>> events = new ArrayList<>();
            for (int i = 0; i < 500; i++) {
                events.add(event(UUID.randomUUID()));
            }
            putEvents(device, sessionId, batch(events)).andExpect(status().isOk());
        }
        putEvents(device, sessionId, batch(List.of(event(UUID.randomUUID()))))
                .andExpect(problem(422, "limit-exceeded"));
    }
}
