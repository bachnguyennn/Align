package com.bachnguyennn.align.reference;

/**
 * Posture state machine: neutral → deviating → sustainedTilt → neutral.
 *
 * <p>Rules (applied to the smoothed tilt of each processed sample):
 * <ul>
 *   <li>neutral → deviating(d) when some direction's component reaches its threshold; d is the
 *       direction with the largest component/threshold ratio. The direction is then locked for the
 *       rest of that deviation (no mid-episode switching, which avoids flicker).</li>
 *   <li>deviating → sustainedTilt once {@code sustainedDuration} has elapsed since onset.</li>
 *   <li>deviating/sustained → neutral once d's component drops below threshold - hysteresis. If
 *       another direction is over its own threshold on that sample, a new deviation starts there.</li>
 *   <li>Leaving sustainedTilt (or {@link #interrupt}) produces a PostureEpisode.</li>
 * </ul>
 */
public final class PostureDetector {

    public enum Phase { NEUTRAL, DEVIATING, SUSTAINED }

    /** Thresholds at or below this are treated as this value (avoids division by zero). */
    public static final double MINIMUM_THRESHOLD_DEGREES = 1e-6;

    public record DetectorOutput(PostureState state, boolean becameSustained, PostureEpisode completedEpisode) {}

    private Phase phase = Phase.NEUTRAL;
    private TiltDirection direction;
    private Double since;
    private double peak = 0.0;
    private boolean reminderTriggered = false;

    /** Signed tilt in {@code direction}: positive means tilted that way. */
    public static double componentDegrees(TiltEstimate tilt, TiltDirection direction) {
        return switch (direction) {
            case FORWARD -> tilt.forwardDegrees();
            case BACKWARD -> -tilt.forwardDegrees();
            case RIGHT -> tilt.lateralDegrees();
            case LEFT -> -tilt.lateralDegrees();
        };
    }

    public static double thresholdDegrees(TiltDirection direction, PostureConfiguration config) {
        double t = switch (direction) {
            case FORWARD -> config.forwardThresholdDegrees();
            case BACKWARD -> config.backwardThresholdDegrees();
            case LEFT, RIGHT -> config.lateralThresholdDegrees();
        };
        return Math.max(t, MINIMUM_THRESHOLD_DEGREES);
    }

    /** Direction whose |angle| / threshold ratio is largest among those at or over threshold, or null. */
    public static TiltDirection dominantDirection(TiltEstimate tilt, PostureConfiguration config) {
        TiltDirection best = null;
        double bestRatio = 0.0;
        for (TiltDirection candidate : TiltDirection.values()) {
            double ratio = componentDegrees(tilt, candidate) / thresholdDegrees(candidate, config);
            if (ratio >= 1.0 && ratio > bestRatio) {
                best = candidate;
                bestRatio = ratio;
            }
        }
        return best;
    }

    public Phase phase() {
        return phase;
    }

    /** Locked direction of the current deviation, or null when neutral. */
    public TiltDirection direction() {
        return direction;
    }

    /** Deviation onset timestamp, or null when neutral. */
    public Double since() {
        return since;
    }

    public boolean reminderTriggered() {
        return reminderTriggered;
    }

    public void reset() {
        phase = Phase.NEUTRAL;
        direction = null;
        since = null;
        peak = 0.0;
        reminderTriggered = false;
    }

    public PostureState state() {
        return switch (phase) {
            case DEVIATING -> PostureState.deviating(direction, since);
            case SUSTAINED -> PostureState.sustainedTilt(direction, since);
            case NEUTRAL -> PostureState.of(PostureState.Kind.NEUTRAL);
        };
    }

    public void markReminderTriggered() {
        reminderTriggered = true;
    }

    private PostureEpisode episode(double endTimestamp) {
        return new PostureEpisode(direction, since, endTimestamp, peak, reminderTriggered);
    }

    /** Closes a sustained episode (if any) at {@code at} and resets to neutral; null if none. */
    public PostureEpisode interrupt(double at) {
        PostureEpisode episode = phase == Phase.SUSTAINED ? episode(at) : null;
        reset();
        return episode;
    }

    public DetectorOutput update(TiltEstimate tilt, PostureConfiguration config) {
        double t = tilt.timestamp();
        PostureEpisode completed = null;
        boolean becameSustained = false;

        if (phase != Phase.NEUTRAL) {
            double value = componentDegrees(tilt, direction);
            double release = thresholdDegrees(direction, config) - config.hysteresisDegrees();
            if (value < release) {
                if (phase == Phase.SUSTAINED) {
                    completed = episode(t);
                }
                reset();
            } else {
                if (value > peak) {
                    peak = value;
                }
                if (phase == Phase.DEVIATING && t - since + Model.TIME_EPSILON >= config.sustainedDuration()) {
                    phase = Phase.SUSTAINED;
                    becameSustained = true;
                }
            }
        }

        if (phase == Phase.NEUTRAL) {
            TiltDirection dominant = dominantDirection(tilt, config);
            if (dominant != null) {
                phase = Phase.DEVIATING;
                direction = dominant;
                since = t;
                peak = componentDegrees(tilt, dominant);
                reminderTriggered = false;
                if (config.sustainedDuration() <= Model.TIME_EPSILON) {
                    phase = Phase.SUSTAINED;
                    becameSustained = true;
                }
            }
        }

        return new DetectorOutput(state(), becameSustained, completed);
    }
}
