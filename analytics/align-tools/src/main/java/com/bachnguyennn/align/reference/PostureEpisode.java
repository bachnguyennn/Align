package com.bachnguyennn.align.reference;

/** AlignCore {@code PostureEpisode}. */
public record PostureEpisode(TiltDirection direction, double startTimestamp, double endTimestamp,
                             double peakDeviationDegrees, boolean reminderTriggered) {}
