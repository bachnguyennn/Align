package com.bachnguyennn.align.server.session;

import com.bachnguyennn.align.server.config.ApiLimits;
import com.bachnguyennn.align.server.session.SessionViews.EventBatchResult;
import com.bachnguyennn.align.server.session.SessionViews.EventView;
import com.bachnguyennn.align.server.session.SessionViews.SessionPage;
import com.bachnguyennn.align.server.session.SessionViews.SessionView;
import com.bachnguyennn.align.server.web.ApiException;
import com.bachnguyennn.align.server.web.FieldViolation;
import com.bachnguyennn.align.server.web.ProblemType;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Session and event storage. Every method is scoped to the calling device. */
@Service
public class SessionService {

    /** Outcome of a session upsert. */
    public enum UpsertOutcome { CREATED, UPDATED, UNCHANGED }

    public record UpsertResult(UpsertOutcome outcome, SessionView session) {
    }

    private final SessionRepository sessions;
    private final PostureEventRepository events;
    private final Clock clock;

    public SessionService(SessionRepository sessions, PostureEventRepository events, Clock clock) {
        this.sessions = sessions;
        this.events = events;
        this.clock = clock;
    }

    @Transactional
    public UpsertResult upsertSession(UUID deviceId, UUID sessionId, SessionUpload rawUpload) {
        SessionUpload upload = rawUpload.normalized();
        validateSession(sessionId, upload);
        Instant now = now();
        SessionEntity existing = sessions.findByDeviceIdAndSessionId(deviceId, sessionId).orElse(null);
        if (existing == null) {
            SessionEntity created = new SessionEntity(deviceId, sessionId, now);
            created.apply(upload);
            sessions.saveAndFlush(created);
            return new UpsertResult(UpsertOutcome.CREATED, SessionView.of(created, null));
        }
        if (existing.matches(upload)) {
            return new UpsertResult(UpsertOutcome.UNCHANGED, SessionView.of(existing, null));
        }
        existing.apply(upload);
        existing.touch(now);
        sessions.flush();
        return new UpsertResult(UpsertOutcome.UPDATED, SessionView.of(existing, null));
    }

    @Transactional(readOnly = true)
    public SessionView getSession(UUID deviceId, UUID sessionId) {
        SessionEntity session = requireSession(deviceId, sessionId);
        List<EventView> eventViews = events.findBySession(session.getPk()).stream().map(EventView::of).toList();
        return SessionView.of(session, eventViews);
    }

    @Transactional(readOnly = true)
    public SessionPage listSessions(UUID deviceId, Instant since, Integer limit, String cursor) {
        int pageSize = limit == null ? ApiLimits.DEFAULT_PAGE_SIZE : limit;
        if (pageSize < 1 || pageSize > ApiLimits.MAX_PAGE_SIZE) {
            throw ApiException.invalidParameter(
                    "Parameter 'limit' must be between 1 and " + ApiLimits.MAX_PAGE_SIZE + ".");
        }
        Instant lowerBound = since == null ? Instant.EPOCH : since;
        PageRequest page = PageRequest.of(0, pageSize + 1);
        List<SessionEntity> rows;
        if (cursor == null || cursor.isEmpty()) {
            rows = sessions.findFirstPage(deviceId, lowerBound, page);
        } else {
            PageCursor after = PageCursor.decode(cursor);
            rows = sessions.findPageAfter(deviceId, lowerBound, after.updatedAt(), after.sessionId(), page);
        }
        boolean more = rows.size() > pageSize;
        List<SessionEntity> visible = more ? rows.subList(0, pageSize) : rows;
        String next = null;
        if (more) {
            SessionEntity last = visible.get(visible.size() - 1);
            next = new PageCursor(last.getUpdatedAt(), last.getSessionId()).encode();
        }
        return new SessionPage(visible.stream().map(s -> SessionView.of(s, null)).toList(), next);
    }

    @Transactional
    public EventBatchResult upsertEvents(UUID deviceId, UUID sessionId, EventBatch batch) {
        SessionEntity session = requireSession(deviceId, sessionId);
        List<EventUpload> uploads = batch.events().stream().map(EventUpload::normalized).toList();
        validateEvents(uploads);

        Map<UUID, PostureEventEntity> existing = new HashMap<>();
        for (PostureEventEntity entity : events.findByDeviceAndEventIds(deviceId,
                uploads.stream().map(EventUpload::id).toList())) {
            if (!entity.getSessionPk().equals(session.getPk())) {
                throw new ApiException(ProblemType.CONFLICT,
                        "Event " + entity.getEventId() + " already belongs to another session of this device.");
            }
            existing.put(entity.getEventId(), entity);
        }

        long newCount = uploads.stream().filter(u -> !existing.containsKey(u.id())).count();
        if (newCount > 0 && events.countBySessionPk(session.getPk()) + newCount > ApiLimits.MAX_EVENTS_PER_SESSION) {
            throw new ApiException(ProblemType.LIMIT_EXCEEDED,
                    "A session can hold at most " + ApiLimits.MAX_EVENTS_PER_SESSION + " events.");
        }

        Instant now = now();
        int created = 0;
        int updated = 0;
        int unchanged = 0;
        List<PostureEventEntity> toSave = new ArrayList<>();
        for (EventUpload upload : uploads) {
            PostureEventEntity entity = existing.get(upload.id());
            if (entity == null) {
                entity = new PostureEventEntity(session.getPk(), deviceId, upload.id(), now);
                entity.apply(upload, now);
                toSave.add(entity);
                created++;
            } else if (entity.matches(upload)) {
                unchanged++;
            } else {
                entity.apply(upload, now);
                updated++;
            }
        }
        events.saveAll(toSave);
        if (created + updated > 0) {
            // Sync clients pull by session updatedAt, so a changed event marks its session changed.
            session.touch(now);
        }
        events.flush();
        return new EventBatchResult(created, updated, unchanged);
    }

    private SessionEntity requireSession(UUID deviceId, UUID sessionId) {
        // Same answer for "does not exist" and "belongs to another device": nothing leaks.
        return sessions.findByDeviceIdAndSessionId(deviceId, sessionId)
                .orElseThrow(() -> ApiException.notFound("No session with this id."));
    }

    private void validateSession(UUID pathId, SessionUpload upload) {
        List<FieldViolation> errors = new ArrayList<>();
        if (upload.id() != null && !upload.id().equals(pathId)) {
            errors.add(new FieldViolation("id", "must equal the id in the path"));
        }
        checkTimestamp("startedAt", upload.startedAt(), errors);
        if (upload.endedAt() != null) {
            checkTimestamp("endedAt", upload.endedAt(), errors);
            if (upload.endedAt().isBefore(upload.startedAt())) {
                errors.add(new FieldViolation("endedAt", "must not be before startedAt"));
            } else if (Duration.between(upload.startedAt(), upload.endedAt()).getSeconds()
                    > ApiLimits.MAX_SESSION_SECONDS) {
                errors.add(new FieldViolation("endedAt", "session must not be longer than 7 days"));
            }
        }
        if (upload.withinThresholdSeconds() + upload.sustainedDeviationSeconds()
                > upload.monitoredDurationSeconds() + ApiLimits.DURATION_SUM_TOLERANCE_SECONDS) {
            errors.add(new FieldViolation("monitoredDurationSeconds",
                    "must be at least withinThresholdSeconds + sustainedDeviationSeconds"));
        }
        if (!errors.isEmpty()) {
            throw ApiException.validation(errors);
        }
    }

    private void validateEvents(List<EventUpload> uploads) {
        List<FieldViolation> errors = new ArrayList<>();
        Set<UUID> seen = new HashSet<>();
        for (int i = 0; i < uploads.size(); i++) {
            EventUpload upload = uploads.get(i);
            String prefix = "events[" + i + "].";
            if (!seen.add(upload.id())) {
                errors.add(new FieldViolation(prefix + "id", "is repeated in this batch"));
            }
            checkTimestamp(prefix + "startedAt", upload.startedAt(), errors);
            checkTimestamp(prefix + "endedAt", upload.endedAt(), errors);
            if (upload.endedAt().isBefore(upload.startedAt())) {
                errors.add(new FieldViolation(prefix + "endedAt", "must not be before startedAt"));
            } else if (Duration.between(upload.startedAt(), upload.endedAt()).getSeconds()
                    > ApiLimits.MAX_EVENT_SECONDS) {
                errors.add(new FieldViolation(prefix + "endedAt", "event must not be longer than 24 hours"));
            }
        }
        if (!errors.isEmpty()) {
            throw ApiException.validation(errors);
        }
    }

    private void checkTimestamp(String field, Instant value, List<FieldViolation> errors) {
        if (value.isBefore(ApiLimits.EARLIEST_TIMESTAMP)) {
            errors.add(new FieldViolation(field, "must not be before " + ApiLimits.EARLIEST_TIMESTAMP));
        } else if (value.isAfter(clock.instant().plus(ApiLimits.MAX_FUTURE_SKEW))) {
            errors.add(new FieldViolation(field, "must not be more than 24 hours in the future"));
        }
    }

    private Instant now() {
        return clock.instant().truncatedTo(ChronoUnit.MICROS);
    }
}
