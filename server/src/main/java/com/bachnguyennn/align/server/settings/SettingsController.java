package com.bachnguyennn.align.server.settings;

import com.bachnguyennn.align.server.auth.DevicePrincipal;
import com.bachnguyennn.align.server.settings.SettingsService.SettingsState;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import java.time.Instant;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping(path = "/api/v1/settings", produces = MediaType.APPLICATION_JSON_VALUE)
public class SettingsController {

    /** Response body; the same version is sent as the ETag header. */
    public record SettingsEnvelope(long version, Instant updatedAt, SettingsDocument settings) {
        static SettingsEnvelope of(SettingsState state) {
            return new SettingsEnvelope(state.version(), state.updatedAt(), state.settings());
        }
    }

    /** Request body of PUT. */
    public record SettingsPut(@NotNull @Valid SettingsDocument settings) {
    }

    private final SettingsService service;

    public SettingsController(SettingsService service) {
        this.service = service;
    }

    @GetMapping
    public ResponseEntity<SettingsEnvelope> get(@AuthenticationPrincipal DevicePrincipal device) {
        return respond(service.get(device.deviceId()));
    }

    @PutMapping(consumes = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<SettingsEnvelope> put(@AuthenticationPrincipal DevicePrincipal device,
            @RequestHeader(name = HttpHeaders.IF_MATCH, required = false) String ifMatch,
            @Valid @RequestBody SettingsPut body) {
        return respond(service.put(device.deviceId(), ifMatch, body.settings()));
    }

    private static ResponseEntity<SettingsEnvelope> respond(SettingsState state) {
        return ResponseEntity.ok().eTag("\"" + state.version() + "\"").body(SettingsEnvelope.of(state));
    }
}
