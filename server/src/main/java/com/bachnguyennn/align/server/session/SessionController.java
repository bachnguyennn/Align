package com.bachnguyennn.align.server.session;

import com.bachnguyennn.align.server.auth.DevicePrincipal;
import com.bachnguyennn.align.server.session.SessionService.UpsertOutcome;
import com.bachnguyennn.align.server.session.SessionService.UpsertResult;
import com.bachnguyennn.align.server.session.SessionViews.EventBatchResult;
import com.bachnguyennn.align.server.session.SessionViews.SessionPage;
import com.bachnguyennn.align.server.session.SessionViews.SessionView;
import com.bachnguyennn.align.server.web.ApiException;
import jakarta.validation.Valid;
import java.net.URI;
import java.time.Instant;
import java.time.format.DateTimeParseException;
import java.util.UUID;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping(path = "/api/v1/sessions", produces = MediaType.APPLICATION_JSON_VALUE)
public class SessionController {

    private final SessionService service;

    public SessionController(SessionService service) {
        this.service = service;
    }

    /** Idempotent upsert: 201 when created, 200 when updated or unchanged. */
    @PutMapping(path = "/{id}", consumes = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<SessionView> putSession(@AuthenticationPrincipal DevicePrincipal device,
            @PathVariable("id") UUID id, @Valid @RequestBody SessionUpload body) {
        UpsertResult result = service.upsertSession(device.deviceId(), id, body);
        if (result.outcome() == UpsertOutcome.CREATED) {
            return ResponseEntity.created(URI.create("/api/v1/sessions/" + id)).body(result.session());
        }
        return ResponseEntity.ok(result.session());
    }

    @GetMapping("/{id}")
    public SessionView getSession(@AuthenticationPrincipal DevicePrincipal device, @PathVariable("id") UUID id) {
        return service.getSession(device.deviceId(), id);
    }

    @GetMapping
    public SessionPage listSessions(@AuthenticationPrincipal DevicePrincipal device,
            @RequestParam(name = "since", required = false) String since,
            @RequestParam(name = "limit", required = false) Integer limit,
            @RequestParam(name = "cursor", required = false) String cursor) {
        return service.listSessions(device.deviceId(), parseInstant("since", since), limit, cursor);
    }

    /** Batch upsert of this session's events by client UUID. */
    @PutMapping(path = "/{id}/events", consumes = MediaType.APPLICATION_JSON_VALUE)
    public EventBatchResult putEvents(@AuthenticationPrincipal DevicePrincipal device,
            @PathVariable("id") UUID id, @Valid @RequestBody EventBatch body) {
        return service.upsertEvents(device.deviceId(), id, body);
    }

    static Instant parseInstant(String name, String value) {
        if (value == null || value.isEmpty()) {
            return null;
        }
        try {
            return java.time.OffsetDateTime.parse(value).toInstant();
        } catch (DateTimeParseException e) {
            throw ApiException.invalidParameter(
                    "Parameter '" + name + "' must be an RFC 3339 timestamp such as 2026-10-31T08:00:00Z.");
        }
    }
}
