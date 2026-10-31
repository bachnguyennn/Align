package com.bachnguyennn.align.server.device;

import com.bachnguyennn.align.server.auth.TokenService;
import com.bachnguyennn.align.server.session.PostureEventRepository;
import com.bachnguyennn.align.server.session.SessionRepository;
import com.bachnguyennn.align.server.settings.SettingsRepository;
import com.bachnguyennn.align.server.web.ApiException;
import java.time.Clock;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DeviceService {

    /** A new registration. {@code token} exists only in this response; the server keeps its hash. */
    public record Registration(UUID deviceId, String token, Instant createdAt) {
        @Override
        public String toString() {
            return "Registration[deviceId=" + deviceId + ", token=<redacted>, createdAt=" + createdAt + "]";
        }
    }

    private final DeviceRepository devices;
    private final SessionRepository sessions;
    private final PostureEventRepository events;
    private final SettingsRepository settings;
    private final TokenService tokens;
    private final Clock clock;

    public DeviceService(DeviceRepository devices, SessionRepository sessions, PostureEventRepository events,
            SettingsRepository settings, TokenService tokens, Clock clock) {
        this.devices = devices;
        this.sessions = sessions;
        this.events = events;
        this.settings = settings;
        this.tokens = tokens;
        this.clock = clock;
    }

    @Transactional
    public Registration register() {
        String token = tokens.newToken();
        DeviceEntity device = new DeviceEntity(UUID.randomUUID(), tokens.hash(token),
                clock.instant().truncatedTo(ChronoUnit.MICROS));
        devices.saveAndFlush(device);
        return new Registration(device.getId(), token, device.getCreatedAt());
    }

    @Transactional(readOnly = true)
    public DeviceEntity get(UUID deviceId) {
        return devices.findById(deviceId).orElseThrow(() -> ApiException.notFound("No such device."));
    }

    /**
     * Erases everything stored for the device: events, sessions, settings and the registration
     * itself (so the token stops working). The foreign keys also cascade; the explicit deletes
     * keep this independent of database behavior.
     */
    @Transactional
    public void erase(UUID deviceId) {
        events.deleteAllByDevice(deviceId);
        sessions.deleteAllByDevice(deviceId);
        settings.deleteAllByDevice(deviceId);
        devices.deleteDevice(deviceId);
    }
}
