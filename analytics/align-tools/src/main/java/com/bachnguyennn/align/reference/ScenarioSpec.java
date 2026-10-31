package com.bachnguyennn.align.reference;

import com.fasterxml.jackson.databind.node.ObjectNode;
import java.util.ArrayList;
import java.util.List;
import java.util.function.Function;

/**
 * A synthetic scenario for {@link Generator} (Python {@code generator.ScenarioSpec}). Mutable with
 * fluent setters, like the Python dataclass with keyword overrides:
 * {@code Generator.steadyNeutral(6000).swayDeg(1.0).microInterval(4.0)}.
 *
 * <p>All times are relative seconds since the fixture's start; angles are degrees.
 */
public final class ScenarioSpec {

    /** A glance: raised-cosine trapezoid of total {@code duration} including {@code ramp}s. */
    public record Glance(double start, double duration, double forward, double lateral, double ramp) {
        public Glance(double start, double duration, double forward) {
            this(start, duration, forward, 0.0, 0.4);
        }
    }

    /** Pose keyframe (cosine-eased between keyframes). */
    public record Keyframe(double t, double forward, double lateral) {}

    /** Half-open time window [start, end). */
    public record Interval(double start, double end) {}

    /** A (forward, lateral) pose in degrees. */
    public record Angles(double forward, double lateral) {}

    /** A fixture action at relative time {@code t}. */
    public record Action(double t, String type) {}

    /** Extra (forward, lateral) pose added to the truth at relative time t. */
    @FunctionalInterface
    public interface Wobble {
        Angles at(double t);
    }

    private final String name;
    private final String description;
    private final long seed;
    private double duration;
    private double sampleRateHz = 25.0;
    private double startTimestamp = 0.0;
    private ObjectNode config = Generator.axesConfig();
    private List<Action> actions = new ArrayList<>();
    private List<Keyframe> keyframes = List.of(new Keyframe(0.0, 0.0, 0.0));
    private List<Glance> glances = new ArrayList<>();
    private List<Interval> gaps = new ArrayList<>();  // no samples with start <= t < end
    private List<Interval> calmWindows = List.of(new Interval(0.0, 11.0));
    private Wobble wobble;
    private double swayDeg = 0.5;
    private double microInterval = 8.0;
    private double sensorNoiseDeg = 0.05;
    private double headTurnInterval = 15.0;
    private double mountPitch = 8.0;
    private double mountRoll = -3.0;
    private double timestampJitter = 0.004;  // std of delivery-time jitter, seconds
    private Function<ScenarioSpec, ObjectNode> expected = spec -> Json.object();

    public ScenarioSpec(String name, String description, long seed, double duration) {
        this.name = name;
        this.description = description;
        this.seed = seed;
        this.duration = duration;
    }

    /** Absolute (fixture) time of a relative time, rounded to 4 decimals. */
    public double absT(double rel) {
        return PythonFormat.round(startTimestamp + rel, 4);
    }

    public String name() { return name; }
    public String description() { return description; }
    public long seed() { return seed; }
    public double duration() { return duration; }
    public double sampleRateHz() { return sampleRateHz; }
    public double startTimestamp() { return startTimestamp; }
    public ObjectNode config() { return config; }
    public List<Action> actions() { return actions; }
    public List<Keyframe> keyframes() { return keyframes; }
    public List<Glance> glances() { return glances; }
    public List<Interval> gaps() { return gaps; }
    public List<Interval> calmWindows() { return calmWindows; }
    public Wobble wobble() { return wobble; }
    public double swayDeg() { return swayDeg; }
    public double microInterval() { return microInterval; }
    public double sensorNoiseDeg() { return sensorNoiseDeg; }
    public double headTurnInterval() { return headTurnInterval; }
    public double mountPitch() { return mountPitch; }
    public double mountRoll() { return mountRoll; }
    public double timestampJitter() { return timestampJitter; }
    public Function<ScenarioSpec, ObjectNode> expected() { return expected; }

    public ScenarioSpec duration(double v) { duration = v; return this; }
    public ScenarioSpec sampleRateHz(double v) { sampleRateHz = v; return this; }
    public ScenarioSpec startTimestamp(double v) { startTimestamp = v; return this; }
    public ScenarioSpec config(ObjectNode v) { config = v; return this; }
    public ScenarioSpec actions(List<Action> v) { actions = v; return this; }
    public ScenarioSpec keyframes(List<Keyframe> v) { keyframes = v; return this; }
    public ScenarioSpec glances(List<Glance> v) { glances = v; return this; }
    public ScenarioSpec gaps(List<Interval> v) { gaps = v; return this; }
    public ScenarioSpec calmWindows(List<Interval> v) { calmWindows = v; return this; }
    public ScenarioSpec wobble(Wobble v) { wobble = v; return this; }
    public ScenarioSpec swayDeg(double v) { swayDeg = v; return this; }
    public ScenarioSpec microInterval(double v) { microInterval = v; return this; }
    public ScenarioSpec sensorNoiseDeg(double v) { sensorNoiseDeg = v; return this; }
    public ScenarioSpec headTurnInterval(double v) { headTurnInterval = v; return this; }
    public ScenarioSpec mountPitch(double v) { mountPitch = v; return this; }
    public ScenarioSpec mountRoll(double v) { mountRoll = v; return this; }
    public ScenarioSpec timestampJitter(double v) { timestampJitter = v; return this; }
    public ScenarioSpec expected(Function<ScenarioSpec, ObjectNode> v) { expected = v; return this; }
}
