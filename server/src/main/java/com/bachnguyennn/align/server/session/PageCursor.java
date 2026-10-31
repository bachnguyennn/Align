package com.bachnguyennn.align.server.session;

import com.bachnguyennn.align.server.web.ApiException;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Base64;
import java.util.UUID;

/**
 * Opaque keyset cursor for {@code GET /sessions}: the (updatedAt, id) of the last item returned.
 * Encoded as base64url of {@code v1|<epochSecond>|<nano>|<uuid>}. Clients must treat it as opaque.
 */
record PageCursor(Instant updatedAt, UUID sessionId) {

    private static final String VERSION = "v1";

    String encode() {
        String raw = VERSION + "|" + updatedAt.getEpochSecond() + "|" + updatedAt.getNano() + "|" + sessionId;
        return Base64.getUrlEncoder().withoutPadding().encodeToString(raw.getBytes(StandardCharsets.US_ASCII));
    }

    static PageCursor decode(String cursor) {
        try {
            if (cursor.length() > 200) {
                throw new IllegalArgumentException("too long");
            }
            String raw = new String(Base64.getUrlDecoder().decode(cursor), StandardCharsets.US_ASCII);
            String[] parts = raw.split("\\|", -1);
            if (parts.length != 4 || !VERSION.equals(parts[0])) {
                throw new IllegalArgumentException("bad format");
            }
            Instant updatedAt = Instant.ofEpochSecond(Long.parseLong(parts[1]), Long.parseLong(parts[2]));
            return new PageCursor(updatedAt, UUID.fromString(parts[3]));
        } catch (RuntimeException e) {
            throw ApiException.invalidParameter("Invalid value for parameter 'cursor'.");
        }
    }
}
