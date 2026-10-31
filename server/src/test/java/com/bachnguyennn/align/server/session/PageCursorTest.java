package com.bachnguyennn.align.server.session;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.bachnguyennn.align.server.web.ApiException;
import java.time.Instant;
import java.util.UUID;
import org.junit.jupiter.api.Test;

class PageCursorTest {

    @Test
    void roundTrips() {
        PageCursor cursor = new PageCursor(Instant.parse("2026-03-02T08:00:00.123456Z"), UUID.randomUUID());
        String encoded = cursor.encode();
        assertThat(encoded).matches("[A-Za-z0-9_-]+");
        assertThat(PageCursor.decode(encoded)).isEqualTo(cursor);
    }

    @Test
    void rejectsGarbage() {
        for (String bad : new String[] {"", "!!!", "djE", "x".repeat(300), "djJ8MXwyfDM"}) {
            assertThatThrownBy(() -> PageCursor.decode(bad)).isInstanceOf(ApiException.class);
        }
    }
}
