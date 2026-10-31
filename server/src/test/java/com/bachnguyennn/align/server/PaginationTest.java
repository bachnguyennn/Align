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
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.web.util.UriComponentsBuilder;

class PaginationTest extends ApiTestSupport {

    private List<UUID> upload(Device device, int count) throws Exception {
        List<UUID> ids = new ArrayList<>();
        for (int i = 0; i < count; i++) {
            UUID id = UUID.randomUUID();
            putSession(device, id, session()).andExpect(status().isCreated());
            ids.add(id);
        }
        return ids;
    }

    private List<String> collect(Device device, String query) throws Exception {
        List<String> seen = new ArrayList<>();
        String cursor = null;
        int pages = 0;
        do {
            UriComponentsBuilder uri = UriComponentsBuilder.fromUriString("/api/v1/sessions" + query);
            if (cursor != null) {
                uri.queryParam("cursor", cursor);
            }
            JsonNode page = body(getAs(device, uri.toUriString()).andExpect(status().isOk()));
            page.get("items").forEach(item -> seen.add(item.get("id").asText()));
            cursor = page.get("nextCursor").isNull() ? null : page.get("nextCursor").asText();
            pages++;
        } while (cursor != null && pages < 100);
        return seen;
    }

    @Test
    void pagesCoverEverySessionExactlyOnce() throws Exception {
        Device device = register();
        List<UUID> ids = upload(device, 5);

        JsonNode first = body(getAs(device, "/api/v1/sessions?limit=2")
                .andExpect(jsonPath("$.items.length()").value(2))
                .andExpect(jsonPath("$.nextCursor").isString()));
        assertThat(first.get("items").get(0).has("events")).isFalse();

        List<String> seen = collect(device, "?limit=2");
        assertThat(seen).containsExactlyInAnyOrderElementsOf(ids.stream().map(UUID::toString).toList());
        assertThat(seen).doesNotHaveDuplicates();

        // Default page holds everything; the last page has a null cursor.
        getAs(device, "/api/v1/sessions")
                .andExpect(jsonPath("$.items.length()").value(5))
                .andExpect(jsonPath("$.nextCursor").isEmpty());
    }

    @Test
    void exactMultipleOfThePageSizeEndsWithoutAnEmptyPage() throws Exception {
        Device device = register();
        upload(device, 4);
        JsonNode second = body(getAs(device, "/api/v1/sessions?limit=2&cursor="
                + body(getAs(device, "/api/v1/sessions?limit=2")).get("nextCursor").asText()));
        assertThat(second.get("items")).hasSize(2);
        assertThat(second.get("nextCursor").isNull()).isTrue();
    }

    @Test
    void sinceReturnsOnlySessionsChangedFromThatInstant() throws Exception {
        Device device = register();
        List<UUID> old = upload(device, 2);
        Thread.sleep(5);
        Instant mark = Instant.now();
        Thread.sleep(5);
        UUID fresh = upload(device, 1).get(0);
        // Updating an old session moves it past the mark as well.
        Map<String, Object> changed = session();
        changed.put("reminderCount", 7);
        putSession(device, old.get(0), changed).andExpect(status().isOk());

        List<String> seen = collect(device, "?since=" + mark + "&limit=1");
        assertThat(seen).containsExactlyInAnyOrder(fresh.toString(), old.get(0).toString());
    }

    @ParameterizedTest(name = "{0}")
    @ValueSource(strings = {"?limit=0", "?limit=201", "?limit=abc", "?cursor=not-a-cursor", "?cursor=djF8eHx5fHo",
            "?since=yesterday", "?since=2026-03-02"})
    void invalidParametersAre400(String query) throws Exception {
        Device device = register();
        getAs(device, "/api/v1/sessions" + query).andExpect(problem(400, "invalid-parameter"));
    }
}
