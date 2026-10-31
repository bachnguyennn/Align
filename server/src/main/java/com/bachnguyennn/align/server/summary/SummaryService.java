package com.bachnguyennn.align.server.summary;

import com.bachnguyennn.align.server.config.ApiLimits;
import com.bachnguyennn.align.server.session.SessionEntity;
import com.bachnguyennn.align.server.session.SessionRepository;
import com.bachnguyennn.align.server.web.ApiException;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Daily summaries computed exactly like the app's {@code DailySummaryBuilder}
 * (ios/AlignApp/Persistence/SessionAccounting.swift): one entry per local calendar day in the
 * requested time zone, oldest first, days without sessions included with zeros; each session is
 * attributed wholly to the local day its {@code startedAt} falls on (a session crossing midnight
 * counts for its start day); minutes are each session's seconds / 60, summed without rounding;
 * open sessions ({@code endedAt} null) are included with their current totals.
 */
@Service
public class SummaryService {

    public record DailySummary(LocalDate date, double totalMonitoredMinutes, double withinThresholdMinutes,
            double sustainedDeviationMinutes, int reminderCount) {
    }

    public record SummaryResponse(LocalDate from, LocalDate to, String timeZone, List<DailySummary> days) {
    }

    private final SessionRepository sessions;

    public SummaryService(SessionRepository sessions) {
        this.sessions = sessions;
    }

    @Transactional(readOnly = true)
    public SummaryResponse summarize(UUID deviceId, LocalDate from, LocalDate to, ZoneId zone) {
        if (to.isBefore(from)) {
            throw ApiException.invalidParameter("Parameter 'to' must not be before 'from'.");
        }
        long days = ChronoUnit.DAYS.between(from, to) + 1;
        if (days > ApiLimits.MAX_SUMMARY_DAYS) {
            throw ApiException.invalidParameter(
                    "The range from 'from' to 'to' must not exceed " + ApiLimits.MAX_SUMMARY_DAYS + " days.");
        }

        Map<LocalDate, double[]> minutes = new LinkedHashMap<>();
        Map<LocalDate, Integer> reminders = new LinkedHashMap<>();
        for (LocalDate day = from; !day.isAfter(to); day = day.plusDays(1)) {
            minutes.put(day, new double[3]);
            reminders.put(day, 0);
        }

        // Start of the first local day through the start of the day after the last (DST-aware).
        List<SessionEntity> rows = sessions.findStartedBetween(deviceId,
                from.atStartOfDay(zone).toInstant(), to.plusDays(1).atStartOfDay(zone).toInstant());
        for (SessionEntity session : rows) {
            LocalDate day = session.getStartedAt().atZone(zone).toLocalDate();
            double[] bucket = minutes.get(day);
            if (bucket == null) {
                continue;
            }
            bucket[0] += session.getMonitoredDurationSeconds() / 60;
            bucket[1] += session.getWithinThresholdSeconds() / 60;
            bucket[2] += session.getSustainedDeviationSeconds() / 60;
            reminders.merge(day, session.getReminderCount(), Integer::sum);
        }

        List<DailySummary> result = new ArrayList<>(minutes.size());
        minutes.forEach((day, m) -> result.add(new DailySummary(day, m[0], m[1], m[2], reminders.get(day))));
        return new SummaryResponse(from, to, zone.getId(), result);
    }
}
