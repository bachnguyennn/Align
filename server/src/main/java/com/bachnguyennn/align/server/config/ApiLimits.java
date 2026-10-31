package com.bachnguyennn.align.server.config;

import java.time.Duration;
import java.time.Instant;

/** Fixed limits from docs/agents/api-contracts.md ("Limits"). Changing one changes the contract. */
public final class ApiLimits {

    /** No timestamp may be earlier than this. */
    public static final Instant EARLIEST_TIMESTAMP = Instant.parse("2020-01-01T00:00:00Z");
    /** Timestamps may be at most this far ahead of the server clock (device clock skew). */
    public static final Duration MAX_FUTURE_SKEW = Duration.ofHours(24);

    /** Longest session (endedAt - startedAt) and largest session duration field, in seconds. */
    public static final double MAX_SESSION_SECONDS = 7 * 24 * 3600;
    public static final String MAX_SESSION_SECONDS_TEXT = "604800";
    /** Tolerance for withinThreshold + sustainedDeviation <= monitored (floating-point sums). */
    public static final double DURATION_SUM_TOLERANCE_SECONDS = 0.01;
    public static final int MAX_REMINDERS_PER_SESSION = 100_000;

    /** Longest single event, in seconds. */
    public static final String MAX_EVENT_SECONDS_TEXT = "86400";
    public static final double MAX_EVENT_SECONDS = 86_400;
    /** Largest peak deviation, in degrees. */
    public static final String MAX_PEAK_DEGREES_TEXT = "180";

    public static final int MAX_EVENTS_PER_REQUEST = 500;
    public static final int MAX_EVENTS_PER_SESSION = 5_000;

    public static final int DEFAULT_PAGE_SIZE = 50;
    public static final int MAX_PAGE_SIZE = 200;

    public static final int MAX_SUMMARY_DAYS = 366;

    /** Largest stored settings document (canonical JSON), in bytes. */
    public static final int MAX_SETTINGS_BYTES = 16_384;

    private ApiLimits() {
    }
}
