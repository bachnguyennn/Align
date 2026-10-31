package com.bachnguyennn.align.reference;

/**
 * Reminder cooldown policy. Evaluated on sustained updates until the episode has reminded.
 * Returns a reminder if no reminder was given yet, or at least {@code cooldown} seconds have
 * passed since the last one. A timestamp earlier than the last reminder (clock base changed) also
 * allows one.
 */
public final class ReminderDecisionEngine {

    private Double lastReminderTimestamp;

    public Double lastReminderTimestamp() {
        return lastReminderTimestamp;
    }

    public void reset() {
        lastReminderTimestamp = null;
    }

    /** The reminder to give now, or null if the cooldown blocks it. */
    public ReminderDecision evaluate(double timestamp, TiltDirection direction, double deviationDegrees,
                                     double sustainedSeconds, double cooldown) {
        Double last = lastReminderTimestamp;
        if (last != null && timestamp >= last && timestamp - last + Model.TIME_EPSILON < cooldown) {
            return null;
        }
        lastReminderTimestamp = timestamp;
        return new ReminderDecision(timestamp, direction, deviationDegrees, sustainedSeconds);
    }
}
