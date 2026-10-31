package com.bachnguyennn.align.reference;

/** AlignCore {@code ReminderDecision}. */
public record ReminderDecision(double timestamp, TiltDirection direction, double deviationDegrees,
                               double sustainedSeconds) {}
