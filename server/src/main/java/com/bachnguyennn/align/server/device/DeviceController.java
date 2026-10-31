package com.bachnguyennn.align.server.device;

import com.bachnguyennn.align.server.auth.DevicePrincipal;
import com.bachnguyennn.align.server.device.DeviceService.Registration;
import java.net.URI;
import java.time.Instant;
import java.util.UUID;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping(path = "/api/v1/devices", produces = MediaType.APPLICATION_JSON_VALUE)
public class DeviceController {

    public record DeviceView(UUID deviceId, Instant createdAt) {
    }

    private final DeviceService service;

    public DeviceController(DeviceService service) {
        this.service = service;
    }

    /** Anonymous registration (D-018). No request body. */
    @PostMapping
    public ResponseEntity<Registration> register() {
        Registration registration = service.register();
        return ResponseEntity.created(URI.create("/api/v1/devices/me"))
                .cacheControl(CacheControl.noStore())
                .body(registration);
    }

    @GetMapping("/me")
    public DeviceView me(@AuthenticationPrincipal DevicePrincipal device) {
        DeviceEntity entity = service.get(device.deviceId());
        return new DeviceView(entity.getId(), entity.getCreatedAt());
    }

    /** Erases all of the device's data and the registration. */
    @DeleteMapping("/me")
    public ResponseEntity<Void> erase(@AuthenticationPrincipal DevicePrincipal device) {
        service.erase(device.deviceId());
        return ResponseEntity.noContent().build();
    }
}
