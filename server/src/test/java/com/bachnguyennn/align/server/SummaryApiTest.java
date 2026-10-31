package com.bachnguyennn.align.server;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/**
 * Daily summaries must match the app's DailySummaryBuilder: local calendar days in the given
 * time zone, a session counted wholly on the day it started, seconds / 60, zero days included.
 */
class SummaryApiTest extends ApiTestSupport {

    private void upload(Device device, String startedAt, String endedAt, double monitored, double within,
            double sustained, int reminders) throws Exception {
        Map<String, Object> body = session(startedAt, endedAt);
        body.put("monitoredDurationSeconds", monitored);
        body.put("withinThresholdSeconds", within);
        body.put("sustainedDeviationSeconds", sustained);
        body.put("reminderCount", reminders);
        putSession(device, UUID.randomUUID(), body).andExpect(status().isCreated());
    }

    private JsonNode summary(Device device, String from, String to, String tz) throws Exception {
        return body(getAs(device, "/api/v1/analytics/summary?from={f}&to={t}&tz={z}", from, to, tz)
                .andExpect(status().isOk()));
    }

    @Test
    void sumsSessionsPerDayAndIncludesEmptyDays() throws Exception {
        Device device = register();
        upload(device, "2026-03-02T08:00:00Z", "2026-03-02T08:30:00Z", 1200, 1080, 120, 2);
        upload(device, "2026-03-02T18:00:00Z", "2026-03-02T19:00:00Z", 3000, 2700, 300, 1);
        upload(device, "2026-03-04T09:00:00Z", null, 600, 600, 0, 0); // still open: counted

        JsonNode result = summary(device, "2026-03-01", "2026-03-05", "UTC");
        assertThat(result.get("from").asText()).isEqualTo("2026-03-01");
        assertThat(result.get("to").asText()).isEqualTo("2026-03-05");
        assertThat(result.get("timeZone").asText()).isEqualTo("UTC");
        JsonNode days = result.get("days");
        assertThat(days).hasSize(5);
        assertDay(days.get(0), "2026-03-01", 0, 0, 0, 0);
        assertDay(days.get(1), "2026-03-02", 70, 63, 7, 3);
        assertDay(days.get(2), "2026-03-03", 0, 0, 0, 0);
        assertDay(days.get(3), "2026-03-04", 10, 10, 0, 0);
        assertDay(days.get(4), "2026-03-05", 0, 0, 0, 0);
    }

    @Test
    void sessionCrossingMidnightCountsWhollyForItsStartDay() throws Exception {
        Device device = register();
        // 23:30 -> 00:45 UTC, 75 minutes monitored.
        upload(device, "2026-03-01T23:30:00Z", "2026-03-02T00:45:00Z", 4500, 3900, 600, 1);
        JsonNode days = summary(device, "2026-03-01", "2026-03-02", "UTC").get("days");
        assertDay(days.get(0), "2026-03-01", 75, 65, 10, 1);
        assertDay(days.get(1), "2026-03-02", 0, 0, 0, 0);
    }

    @Test
    void localDayFollowsTheRequestedTimeZone() throws Exception {
        Device device = register();
        // 2026-03-10T06:30Z is 23:30 on 2026-03-09 in Los Angeles (PDT, UTC-7) and 15:30 on
        // 2026-03-10 in Tokyo (UTC+9). The session crosses local midnight in Los Angeles.
        upload(device, "2026-03-10T06:30:00Z", "2026-03-10T07:30:00Z", 3600, 3000, 600, 2);
        // 2026-03-10T16:00Z is 01:00 on 2026-03-11 in Tokyo.
        upload(device, "2026-03-10T16:00:00Z", "2026-03-10T16:30:00Z", 1800, 1800, 0, 0);

        JsonNode la = summary(device, "2026-03-09", "2026-03-11", "America/Los_Angeles").get("days");
        assertDay(la.get(0), "2026-03-09", 60, 50, 10, 2);
        assertDay(la.get(1), "2026-03-10", 30, 30, 0, 0);
        assertDay(la.get(2), "2026-03-11", 0, 0, 0, 0);

        JsonNode tokyo = summary(device, "2026-03-09", "2026-03-11", "Asia/Tokyo").get("days");
        assertDay(tokyo.get(0), "2026-03-09", 0, 0, 0, 0);
        assertDay(tokyo.get(1), "2026-03-10", 60, 50, 10, 2);
        assertDay(tokyo.get(2), "2026-03-11", 30, 30, 0, 0);

        JsonNode utc = summary(device, "2026-03-09", "2026-03-11", "UTC").get("days");
        assertDay(utc.get(1), "2026-03-10", 90, 80, 10, 2);
    }

    @Test
    void daylightSavingEndUsesThe25HourLocalDay() throws Exception {
        Device device = register();
        // Berlin leaves summer time on 2026-10-25 at 01:00Z; that local day lasts 25 hours.
        // 22:30Z = 23:30 CET on 10-25; 23:30Z = 00:30 CET on 10-26.
        upload(device, "2026-10-25T22:30:00Z", "2026-10-25T22:40:00Z", 600, 600, 0, 0);
        upload(device, "2026-10-25T23:30:00Z", "2026-10-25T23:40:00Z", 600, 300, 300, 1);
        // 2026-10-24T22:30Z = 00:30 CEST on 10-25 (first hour of the long day).
        upload(device, "2026-10-24T22:30:00Z", "2026-10-24T22:36:00Z", 360, 360, 0, 0);

        JsonNode days = summary(device, "2026-10-24", "2026-10-26", "Europe/Berlin").get("days");
        assertDay(days.get(0), "2026-10-24", 0, 0, 0, 0);
        assertDay(days.get(1), "2026-10-25", 16, 16, 0, 0);
        assertDay(days.get(2), "2026-10-26", 10, 5, 5, 1);
    }

    @Test
    void minutesAreNotRounded() throws Exception {
        Device device = register();
        upload(device, "2026-03-02T08:00:00Z", "2026-03-02T08:01:00Z", 50, 40, 10, 0);
        JsonNode day = summary(device, "2026-03-02", "2026-03-02", "UTC").get("days").get(0);
        assertThat(day.get("totalMonitoredMinutes").asDouble()).isEqualTo(50.0 / 60);
        assertThat(day.get("withinThresholdMinutes").asDouble()).isEqualTo(40.0 / 60);
        assertThat(day.get("sustainedDeviationMinutes").asDouble()).isEqualTo(10.0 / 60);
    }

    @Test
    void singleDayAndMaximumRangeAreAccepted() throws Exception {
        Device device = register();
        assertThat(summary(device, "2026-03-02", "2026-03-02", "UTC").get("days")).hasSize(1);
        assertThat(summary(device, "2025-01-01", "2026-01-01", "UTC").get("days")).hasSize(366);
    }

    @ParameterizedTest(name = "{0}")
    @ValueSource(strings = {
            "from=2026-03-05&to=2026-03-01&tz=UTC",
            "from=2025-01-01&to=2026-01-02&tz=UTC",
            "from=2026-03-01&to=2026-03-05&tz=Mars/Olympus",
            "from=2026-03-01&to=2026-03-05&tz=../etc",
            "from=2026-03-01&to=2026-03-05",
            "from=2026-03-01&tz=UTC",
            "from=03/01/2026&to=2026-03-05&tz=UTC",
            "from=2026-03-01&to=2026-03-05T00:00:00Z&tz=UTC"})
    void invalidParametersAre400(String query) throws Exception {
        Device device = register();
        getAs(device, "/api/v1/analytics/summary?" + query).andExpect(problem(400, "invalid-parameter"));
    }

    private static void assertDay(JsonNode day, String date, double monitored, double within, double sustained,
            int reminders) {
        assertThat(day.get("date").asText()).isEqualTo(date);
        assertThat(day.get("totalMonitoredMinutes").asDouble()).as(date + " monitored").isEqualTo(monitored);
        assertThat(day.get("withinThresholdMinutes").asDouble()).as(date + " within").isEqualTo(within);
        assertThat(day.get("sustainedDeviationMinutes").asDouble()).as(date + " sustained").isEqualTo(sustained);
        assertThat(day.get("reminderCount").asInt()).as(date + " reminders").isEqualTo(reminders);
    }
}
