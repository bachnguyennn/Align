package com.bachnguyennn.align.server.settings;

import com.bachnguyennn.align.server.config.ApiLimits;
import com.bachnguyennn.align.server.web.ApiException;
import com.bachnguyennn.align.server.web.ProblemType;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * The per-device settings document with optimistic concurrency: a write must name the version it
 * is based on (If-Match), and fails with 412 if another write got there first.
 */
@Service
public class SettingsService {

    /** Current state. {@code version} 0 means "never written" (updatedAt null, empty settings). */
    public record SettingsState(long version, Instant updatedAt, SettingsDocument settings) {
    }

    private static final Pattern STRONG_ETAG = Pattern.compile("\"(\\d{1,18})\"");

    private final SettingsRepository repository;
    private final ObjectMapper objectMapper;
    private final TransactionTemplate transactions;
    private final TransactionTemplate readOnlyTransactions;
    private final Clock clock;

    public SettingsService(SettingsRepository repository, ObjectMapper objectMapper,
            PlatformTransactionManager transactionManager, Clock clock) {
        this.repository = repository;
        this.objectMapper = objectMapper;
        this.transactions = new TransactionTemplate(transactionManager);
        this.readOnlyTransactions = new TransactionTemplate(transactionManager);
        this.readOnlyTransactions.setReadOnly(true);
        this.clock = clock;
    }

    public SettingsState get(UUID deviceId) {
        return readOnlyTransactions.execute(status -> repository.findById(deviceId)
                .map(this::state)
                .orElseGet(() -> new SettingsState(0, null, SettingsDocument.empty())));
    }

    public SettingsState put(UUID deviceId, String ifMatch, SettingsDocument document) {
        Long expected = parseIfMatch(ifMatch);
        String json = serialize(document);
        try {
            return transactions.execute(status -> write(deviceId, expected, json));
        } catch (DataIntegrityViolationException e) {
            // A concurrent first write inserted the row between our read and insert.
            throw preconditionFailed();
        }
    }

    private SettingsState write(UUID deviceId, Long expectedOrAny, String json) {
        SettingsEntity current = repository.findById(deviceId).orElse(null);
        long currentVersion = current == null ? 0 : current.getVersion();
        if (expectedOrAny == null) {
            if (current == null) {
                throw preconditionFailed();
            }
        } else if (expectedOrAny != currentVersion) {
            throw preconditionFailed();
        }
        if (current != null && current.getDocument().equals(json)) {
            return state(current);
        }
        Instant now = clock.instant().truncatedTo(ChronoUnit.MICROS);
        if (current == null) {
            SettingsEntity created = repository.saveAndFlush(new SettingsEntity(deviceId, 1, json, now));
            return state(created);
        }
        if (repository.updateIfVersion(deviceId, currentVersion, json, now) == 0) {
            throw preconditionFailed();
        }
        return state(repository.findById(deviceId).orElseThrow());
    }

    /** Returns the expected version, or null for {@code If-Match: *}. */
    static Long parseIfMatch(String ifMatch) {
        if (ifMatch == null || ifMatch.isBlank()) {
            throw new ApiException(ProblemType.PRECONDITION_REQUIRED,
                    "Send If-Match with the ETag from GET /api/v1/settings (\"0\" if there is no document yet).");
        }
        String value = ifMatch.trim();
        if (value.equals("*")) {
            return null;
        }
        Matcher matcher = STRONG_ETAG.matcher(value);
        if (!matcher.matches()) {
            throw preconditionFailed();
        }
        return Long.parseLong(matcher.group(1));
    }

    private String serialize(SettingsDocument document) {
        String json;
        try {
            json = objectMapper.writeValueAsString(document);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("Settings document could not be serialized", e);
        }
        if (json.getBytes(StandardCharsets.UTF_8).length > ApiLimits.MAX_SETTINGS_BYTES) {
            throw new ApiException(ProblemType.LIMIT_EXCEEDED,
                    "The settings document must not exceed " + ApiLimits.MAX_SETTINGS_BYTES + " bytes.");
        }
        return json;
    }

    private SettingsState state(SettingsEntity entity) {
        try {
            return new SettingsState(entity.getVersion(), entity.getUpdatedAt(),
                    objectMapper.readValue(entity.getDocument(), SettingsDocument.class));
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("Stored settings document is unreadable", e);
        }
    }

    private static ApiException preconditionFailed() {
        return new ApiException(ProblemType.PRECONDITION_FAILED,
                "The settings changed since you read them. GET them again, merge, and retry with the new ETag.");
    }
}
