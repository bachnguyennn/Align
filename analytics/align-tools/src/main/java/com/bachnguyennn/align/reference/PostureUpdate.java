package com.bachnguyennn.align.reference;

/** AlignCore {@code PostureUpdate}; every field but {@code timestamp} and {@code state} may be null. */
public record PostureUpdate(double timestamp, PostureState state, TiltEstimate tilt, ReminderDecision reminder,
                            PostureEpisode completedEpisode, CalibrationOutcome calibrationOutcome) {}
