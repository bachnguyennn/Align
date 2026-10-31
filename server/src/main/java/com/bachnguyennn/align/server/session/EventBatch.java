package com.bachnguyennn.align.server.session;

import com.bachnguyennn.align.server.config.ApiLimits;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.util.List;

/** Body of {@code PUT /api/v1/sessions/{id}/events}. */
public record EventBatch(
        @NotNull @Size(min = 1, max = ApiLimits.MAX_EVENTS_PER_REQUEST) List<@NotNull @Valid EventUpload> events) {
}
