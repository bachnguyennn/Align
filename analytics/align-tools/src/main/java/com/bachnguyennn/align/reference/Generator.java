package com.bachnguyennn.align.reference;

import static com.bachnguyennn.align.reference.Geometry.gravityInHeadFrame;
import static com.bachnguyennn.align.reference.Geometry.normalized;
import static com.bachnguyennn.align.reference.Geometry.quatFromRotationVector;
import static com.bachnguyennn.align.reference.Geometry.quatRotate;

import com.bachnguyennn.align.reference.Geometry.Quat;
import com.bachnguyennn.align.reference.Geometry.Vec3;
import com.bachnguyennn.align.reference.ScenarioSpec.Action;
import com.bachnguyennn.align.reference.ScenarioSpec.Angles;
import com.bachnguyennn.align.reference.ScenarioSpec.Glance;
import com.bachnguyennn.align.reference.ScenarioSpec.Interval;
import com.bachnguyennn.align.reference.ScenarioSpec.Keyframe;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.SplittableRandom;
import java.util.function.Supplier;

/**
 * Synthetic AirPods head-motion fixture generator.
 *
 * <p>Model (all angles in degrees):
 * <ul>
 *   <li>True head pose = keyframes (cosine-eased) + glances (raised-cosine trapezoids): forward
 *       flexion (+ = chin to chest) and lateral bend (+ = right ear to right shoulder).</li>
 *   <li>Natural sway: Ornstein-Uhlenbeck process per axis (std {@code swayDeg}, time constant
 *       1.5 s) plus a 0.25 Hz breathing component on the forward axis.</li>
 *   <li>Micro-movements: Poisson (mean every {@code microInterval} s) raised-cosine bumps of
 *       N(0, 1.5 deg) (clipped to ±4 deg), 0.6-2 s long, suppressed during calibration windows
 *       (the user is asked to hold still).</li>
 *   <li>Heading: slow random walk plus occasional head turns of 15-45 deg (heading must not
 *       matter).</li>
 *   <li>Earbud mounting offset ({@code mountPitch}, {@code mountRoll}) between head frame and
 *       device frame.</li>
 *   <li>Sensor noise: white rotation noise of {@code sensorNoiseDeg} per axis on the gravity
 *       vector.</li>
 * </ul>
 *
 * <p>Frames: world is Z-up (Core Motion xArbitraryZVertical), gravity (0, 0, -1) g. Head frame
 * (D-011, unverified on hardware): +X right ear, +Y nose, +Z up at neutral. Axes are never
 * hard-coded: they come from the fixture's configuration ({@code forwardAxis}/{@code lateralAxis},
 * written explicitly into every fixture and equal to the AlignCore default (-1,0,0)/(0,1,0)).
 * Device attitude q = Yaw(heading) * Tilt(forward*forwardAxis + lateral*lateralAxis) * Mount
 * (pitch about forwardAxis, roll about lateralAxis); gravity in the device frame = q* (0,0,-1) q
 * (see {@link Pose}).
 *
 * <p>Randomness: this is a port of the Python generator's model, not of numpy's random streams,
 * so for the same seed it produces different samples than the Python version (the committed
 * fixtures were written by Python). Output is deterministic for a given seed and does not depend
 * on the JDK version or platform: it uses only {@link SplittableRandom#nextDouble()} (Box-Muller
 * for normals) and {@link StrictMath}. The noise-free truth, and therefore {@code expected}, is
 * identical to the Python version.
 *
 * <p>Run {@code ./mvnw -q compile exec:java@generate} (from analytics/align-tools) to rewrite
 * shared/fixtures/motion/*.json, or add {@code -Dexec.args="--out <dir>"} to write elsewhere.
 */
public final class Generator {

    public static final String GENERATOR_SCRIPT =
            "analytics/align-tools/src/main/java/com/bachnguyennn/align/reference/Generator.java";
    public static final double RAD = Math.PI / 180.0;
    public static final List<Action> CALIBRATE_AT_START = List.of(new Action(0.0, "beginCalibration"));

    private Generator() {}

    /** {@code {"forwardAxis": [...], "lateralAxis": [...]}} of the default convention (a new node). */
    public static ObjectNode axesConfig() {
        HeadAxisConvention axes = HeadAxisConvention.DEFAULT;
        ObjectNode config = Json.object();
        config.set("forwardAxis", vec3(axes.forwardAxis()));
        config.set("lateralAxis", vec3(axes.lateralAxis()));
        return config;
    }

    private static ArrayNode vec3(Vec3 v) {
        return Json.array(v.x(), v.y(), v.z());
    }

    // MARK: - Random numbers (stand-ins for the numpy Generator calls of the Python version)

    /** Seeded source of the distributions the model needs. */
    static final class Rng {
        private final SplittableRandom random;

        Rng(long seed) {
            random = new SplittableRandom(seed);
        }

        /** Uniform in [lo, hi). */
        double uniform(double lo, double hi) {
            return lo + (hi - lo) * random.nextDouble();
        }

        /** Standard normal (Box-Muller; one normal per pair of uniforms). */
        double normal() {
            double u1 = 1.0 - random.nextDouble();  // (0, 1], so the log is finite
            double u2 = random.nextDouble();
            return StrictMath.sqrt(-2.0 * StrictMath.log(u1)) * StrictMath.cos(2.0 * Math.PI * u2);
        }

        double normal(double mean, double std) {
            return mean + std * normal();
        }

        /** Exponential with mean {@code scale}. */
        double exponential(double scale) {
            return -scale * StrictMath.log(1.0 - random.nextDouble());
        }
    }

    // MARK: - Truth profile

    private static double ease(double u) {
        return (1.0 - StrictMath.cos(Math.PI * u)) / 2.0;
    }

    public static Angles keyframePose(List<Keyframe> keyframes, double t) {
        Keyframe first = keyframes.get(0);
        if (t <= first.t()) {
            return new Angles(first.forward(), first.lateral());
        }
        for (int i = 0; i + 1 < keyframes.size(); i++) {
            Keyframe k0 = keyframes.get(i);
            Keyframe k1 = keyframes.get(i + 1);
            if (k0.t() <= t && t < k1.t()) {
                double s = ease((t - k0.t()) / (k1.t() - k0.t()));
                return new Angles(k0.forward() + (k1.forward() - k0.forward()) * s,
                        k0.lateral() + (k1.lateral() - k0.lateral()) * s);
            }
        }
        Keyframe last = keyframes.get(keyframes.size() - 1);
        return new Angles(last.forward(), last.lateral());
    }

    public static double glanceEnvelope(Glance g, double t) {
        if (t < g.start() || t > g.start() + g.duration()) {
            return 0.0;
        }
        double x = t - g.start();
        if (x < g.ramp()) {
            return ease(x / g.ramp());
        }
        if (x > g.duration() - g.ramp()) {
            return ease((g.duration() - x) / g.ramp());
        }
        return 1.0;
    }

    /** Noise-free intended pose (forward, lateral) at relative time t. */
    public static Angles truthPose(ScenarioSpec spec, double t) {
        Angles k = keyframePose(spec.keyframes(), t);
        double f = k.forward();
        double l = k.lateral();
        for (Glance g : spec.glances()) {
            double e = glanceEnvelope(g, t);
            f += g.forward() * e;
            l += g.lateral() * e;
        }
        if (spec.wobble() != null) {
            Angles w = spec.wobble().at(t);
            f += w.forward();
            l += w.lateral();
        }
        return new Angles(f, l);
    }

    /** Predicate on a truth pose (forward, lateral). */
    @FunctionalInterface
    public interface PosePredicate {
        boolean test(double forward, double lateral);
    }

    /** First relative time ≥ {@code after} (in 1 ms steps) where the predicate holds on the truth. */
    public static double firstTime(ScenarioSpec spec, PosePredicate predicate, double after) {
        double step = 0.001;
        double t = after;
        while (t <= spec.duration()) {
            Angles a = truthPose(spec, t);
            if (predicate.test(a.forward(), a.lateral())) {
                return t;
            }
            t += step;
        }
        throw new IllegalStateException(spec.name() + ": predicate never true after " + after);
    }

    // MARK: - Synthesis

    private static double[] ou(Rng rng, int n, double dt, double std, double tau) {
        double a = StrictMath.exp(-dt / tau);
        double b = std * StrictMath.sqrt(1.0 - a * a);
        double[] out = new double[n];
        double x = rng.normal(0.0, std);
        for (int i = 0; i < n; i++) {
            x = a * x + b * rng.normal();
            out[i] = x;
        }
        return out;
    }

    private static double[] bumps(Rng rng, double[] times, double interval, double ampStd, double clip,
                                  double minDuration, double maxDuration, List<Interval> calm) {
        double[] out = new double[times.length];
        if (interval <= 0) {
            return out;
        }
        double t = rng.exponential(interval);
        double end = times.length > 0 ? times[times.length - 1] : 0.0;
        while (t < end) {
            double d = rng.uniform(minDuration, maxDuration);
            double amp = Math.min(clip, Math.max(-clip, rng.normal(0.0, ampStd)));
            boolean inCalm = false;
            for (Interval w : calm) {
                if (w.start() - d <= t && t <= w.end()) {
                    inCalm = true;
                    break;
                }
            }
            if (!inCalm) {
                for (int i = 0; i < times.length; i++) {
                    if (times[i] >= t && times[i] <= t + d) {
                        double u = (times[i] - t) / d;
                        double s = StrictMath.sin(Math.PI * u);
                        out[i] += amp * (s * s);
                    }
                }
            }
            t += d + rng.exponential(interval);
        }
        return out;
    }

    /** Noise-free truth at each kept sample (absolute t), for evaluation. */
    public record Truth(double[] t, double[] forward, double[] lateral) {}

    /** A synthesized fixture (without {@code reference}) and its truth. */
    public record Synthesis(ObjectNode fixture, Truth truth) {}

    public static Synthesis synthesize(ScenarioSpec spec) {
        Rng rng = new Rng(spec.seed());
        double dt = 1.0 / spec.sampleRateHz();
        int nTotal = (int) Math.rint(spec.duration() * spec.sampleRateHz()) + 1;
        double[] relAll = new double[nTotal];
        boolean[] keep = new boolean[nTotal];
        for (int i = 0; i < nTotal; i++) {
            relAll[i] = i * dt;
            keep[i] = true;
            for (Interval gap : spec.gaps()) {
                if (relAll[i] >= gap.start() - 1e-9 && relAll[i] < gap.end() - 1e-9) {
                    keep[i] = false;
                }
            }
        }

        double[] swayF = ou(rng, nTotal, dt, spec.swayDeg(), 1.5);
        double breathingPhase = rng.uniform(0, 2 * Math.PI);
        for (int i = 0; i < nTotal; i++) {
            swayF[i] += 0.3 * spec.swayDeg() * StrictMath.sin(2 * Math.PI * 0.25 * relAll[i] + breathingPhase);
        }
        double[] swayL = ou(rng, nTotal, dt, spec.swayDeg() * 0.8, 1.5);
        double[] microF = bumps(rng, relAll, spec.microInterval(), 1.5, 4.0, 0.6, 2.0, spec.calmWindows());
        double[] microL = bumps(rng, relAll, spec.microInterval() * 1.5, 1.2, 3.0, 0.6, 2.0, spec.calmWindows());
        double[] heading = new double[nTotal];
        double walk = 0.0;
        for (int i = 0; i < nTotal; i++) {
            walk += rng.normal(0.0, 0.05);
            heading[i] = walk;
        }
        double headingOffset = rng.uniform(-180, 180);
        double[] turns = bumps(rng, relAll, spec.headTurnInterval(), 30.0, 45.0, 1.0, 3.0, List.of());
        for (int i = 0; i < nTotal; i++) {
            heading[i] = heading[i] + headingOffset + turns[i];
        }
        Vec3[] noise = new Vec3[nTotal];
        double noiseStd = spec.sensorNoiseDeg() * RAD;
        for (int i = 0; i < nTotal; i++) {
            noise[i] = new Vec3(rng.normal(0.0, noiseStd), rng.normal(0.0, noiseStd), rng.normal(0.0, noiseStd));
        }

        // Delivery jitter: real AirPods deliver ~25 Hz with jitter; the pipeline must use timestamps.
        double[] jitter = new double[nTotal];
        for (int i = 0; i < nTotal; i++) {
            jitter[i] = Math.min(0.3 * dt, Math.max(-0.3 * dt, rng.normal(0.0, spec.timestampJitter())));
        }
        HeadAxisConvention axes = PostureConfiguration.fromOverrides(spec.config()).axes();

        ArrayNode samples = Json.array();
        List<Double> truthT = new ArrayList<>();
        List<Double> truthF = new ArrayList<>();
        List<Double> truthL = new ArrayList<>();
        for (int i = 0; i < nTotal; i++) {
            if (!keep[i]) {
                continue;
            }
            double rel = relAll[i];
            Angles truth = truthPose(spec, rel);
            double f = truth.forward() + swayF[i] + microF[i];
            double l = truth.lateral() + swayL[i] + microL[i];
            Quat q = Pose.poseAttitude(f, l, heading[i], spec.mountPitch(), spec.mountRoll(), axes);
            Vec3 g = gravityInHeadFrame(q);
            g = normalized(quatRotate(quatFromRotationVector(noise[i]), g));
            if (q.w() < 0) {
                q = new Quat(-q.x(), -q.y(), -q.z(), -q.w());
            }
            double tJittered = i > 0 ? rel + jitter[i] : rel;
            ObjectNode s = samples.addObject();
            s.put("t", PythonFormat.round(spec.startTimestamp() + tJittered, 4));
            s.set("q", Json.array(PythonFormat.round(q.x(), 4), PythonFormat.round(q.y(), 4),
                    PythonFormat.round(q.z(), 4), PythonFormat.round(q.w(), 4)));
            s.set("g", Json.array(PythonFormat.round(g.x(), 5), PythonFormat.round(g.y(), 5),
                    PythonFormat.round(g.z(), 5)));
            truthT.add(spec.startTimestamp() + rel);
            truthF.add(truth.forward());
            truthL.add(truth.lateral());
        }

        ObjectNode fixture = Json.object();
        fixture.put("schemaVersion", Fixtures.SCHEMA_VERSION);
        fixture.put("name", spec.name());
        fixture.put("description", spec.description());
        ObjectNode generator = fixture.putObject("generator");
        generator.put("script", GENERATOR_SCRIPT);
        generator.put("version", AlignReference.VERSION);
        generator.put("seed", spec.seed());
        generator.put("runtime", "java " + System.getProperty("java.version"));
        fixture.put("sampleRateHz", spec.sampleRateHz());
        fixture.put("startTimestamp", spec.startTimestamp());
        fixture.set("config", spec.config().deepCopy());
        fixture.putNull("baseline");
        ArrayNode actions = fixture.putArray("actions");
        for (Action a : spec.actions()) {
            ObjectNode o = actions.addObject();
            o.put("t", spec.absT(a.t()));
            o.put("type", a.type());
        }
        ObjectNode truth = fixture.putObject("truth");
        ArrayNode keyframes = truth.putArray("keyframes");
        for (Keyframe k : spec.keyframes()) {
            keyframes.add(Json.array(spec.absT(k.t()), k.forward(), k.lateral()));
        }
        ArrayNode glances = truth.putArray("glances");
        for (Glance g : spec.glances()) {
            ObjectNode o = glances.addObject();
            o.put("start", spec.absT(g.start()));
            o.put("duration", g.duration());
            o.put("forward", g.forward());
            o.put("lateral", g.lateral());
        }
        ArrayNode gaps = truth.putArray("gaps");
        for (Interval gap : spec.gaps()) {
            gaps.add(Json.array(spec.absT(gap.start()), spec.absT(gap.end())));
        }
        ObjectNode mount = truth.putObject("mountDegrees");
        mount.put("pitch", spec.mountPitch());
        mount.put("roll", spec.mountRoll());
        truth.put("swayDegrees", spec.swayDeg());
        fixture.set("expected", spec.expected().apply(spec));
        fixture.set("samples", samples);
        return new Synthesis(fixture, new Truth(toArray(truthT), toArray(truthF), toArray(truthL)));
    }

    private static double[] toArray(List<Double> values) {
        return values.stream().mapToDouble(Double::doubleValue).toArray();
    }

    // MARK: - Expected-outcome helpers (derived from the noise-free truth, not from the detector)

    private static PostureConfiguration cfg(ScenarioSpec spec) {
        return PostureConfiguration.fromOverrides(spec.config());
    }

    private static double component(TiltDirection direction, double f, double l) {
        return switch (direction) {
            case FORWARD -> f;
            case BACKWARD -> -f;
            case RIGHT -> l;
            case LEFT -> -l;
        };
    }

    private static double threshold(TiltDirection direction, PostureConfiguration c) {
        return switch (direction) {
            case FORWARD -> c.forwardThresholdDegrees();
            case BACKWARD -> c.backwardThresholdDegrees();
            case LEFT, RIGHT -> c.lateralThresholdDegrees();
        };
    }

    /** Onset and release relative times of a truth episode. */
    public record EpisodeTimes(double onset, double release) {}

    /**
     * Relative times on the truth: first reaching threshold after {@code after}, then first
     * falling below threshold - hysteresis ({@code endOverride} replaces the release if not null).
     */
    public static EpisodeTimes truthEpisode(ScenarioSpec spec, TiltDirection direction, double after,
                                            Double endOverride) {
        PostureConfiguration c = cfg(spec);
        double th = threshold(direction, c);
        double onset = firstTime(spec, (f, l) -> component(direction, f, l) >= th, after);
        if (endOverride != null) {
            return new EpisodeTimes(onset, endOverride);
        }
        double release = firstTime(spec, (f, l) -> component(direction, f, l) < th - c.hysteresisDegrees(), onset);
        return new EpisodeTimes(onset, release);
    }

    public static EpisodeTimes truthEpisode(ScenarioSpec spec, TiltDirection direction, double after) {
        return truthEpisode(spec, direction, after, null);
    }

    /** An expected episode; {@code reminderAt} is null when no reminder is expected. */
    record ExpectedEpisode(TiltDirection direction, double start, double end, boolean reminderTriggered,
                           Double reminderAt) {}

    static ObjectNode expected(List<String> calibration, List<ExpectedEpisode> episodes, String finalState) {
        double tolerance = 2.0;
        ObjectNode out = Json.object();
        ArrayNode outcomes = out.putArray("calibrationOutcomes");
        calibration.forEach(outcomes::add);
        ArrayNode reminders = out.putArray("reminders");
        for (ExpectedEpisode e : episodes) {
            if (e.reminderAt() != null) {
                ObjectNode r = reminders.addObject();
                r.put("t", e.reminderAt());
                r.put("direction", e.direction().rawValue());
            }
        }
        ArrayNode eps = out.putArray("episodes");
        for (ExpectedEpisode e : episodes) {
            ObjectNode o = eps.addObject();
            o.put("direction", e.direction().rawValue());
            o.put("start", e.start());
            o.put("end", e.end());
            o.put("reminderTriggered", e.reminderTriggered());
        }
        out.put("finalState", finalState);
        out.putObject("tolerances").put("timeSeconds", tolerance);
        return out;
    }

    static ExpectedEpisode episode(ScenarioSpec spec, TiltDirection direction, double after, boolean reminder,
                                   Double endOverride) {
        PostureConfiguration c = cfg(spec);
        EpisodeTimes times = truthEpisode(spec, direction, after, endOverride);
        return new ExpectedEpisode(
                direction,
                spec.absT(PythonFormat.round(times.onset(), 2)),
                spec.absT(PythonFormat.round(times.release(), 2)),
                reminder,
                reminder ? spec.absT(PythonFormat.round(times.onset() + c.sustainedDuration(), 2)) : null);
    }

    static ExpectedEpisode episode(ScenarioSpec spec, TiltDirection direction, double after, boolean reminder) {
        return episode(spec, direction, after, reminder, null);
    }

    private static List<Keyframe> keyframes(double[][] rows) {
        List<Keyframe> out = new ArrayList<>();
        for (double[] r : rows) {
            out.add(new Keyframe(r[0], r[1], r[2]));
        }
        return out;
    }

    // MARK: - Scenarios

    public static ScenarioSpec steadyNeutral() {
        return steadyNeutral(101);
    }

    public static ScenarioSpec steadyNeutral(long seed) {
        return new ScenarioSpec("steady_neutral",
                "Calibrate, then 60 s of neutral posture with natural sway, micro-movements and "
                        + "head turns (heading changes). Expect no reminders and no episodes.",
                seed, 55.0)
                .actions(new ArrayList<>(CALIBRATE_AT_START))
                .expected(s -> expected(List.of("succeeded"), List.of(), "neutral"));
    }

    public static ScenarioSpec gradualForwardSlouch() {
        return gradualForwardSlouch(102);
    }

    public static ScenarioSpec gradualForwardSlouch(long seed) {
        return new ScenarioSpec("gradual_forward_slouch",
                "Calibrate, neutral until 20 s, drift to 24 deg forward over 10 s, hold 60 s, "
                        + "return over 5 s. Expect one forward reminder ~30 s after crossing 15 deg.",
                seed, 102.0)
                .actions(new ArrayList<>(CALIBRATE_AT_START))
                .keyframes(keyframes(new double[][] {{0, 0, 0}, {20, 0, 0}, {30, 24, 0}, {90, 24, 0}, {95, 0, 0}}))
                .expected(s -> expected(List.of("succeeded"),
                        List.of(episode(s, TiltDirection.FORWARD, 11, true)), "neutral"));
    }

    public static ScenarioSpec briefGlancesDown() {
        return briefGlancesDown(103);
    }

    public static ScenarioSpec briefGlancesDown(long seed) {
        Rng rng = new Rng(seed + 1000);
        List<Glance> glances = new ArrayList<>();
        double t = 15.0;
        while (t < 64.0) {
            double d = rng.uniform(3.0, 5.0);
            double start = PythonFormat.round(t, 2);
            double duration = PythonFormat.round(d, 2);
            double forward = PythonFormat.round(rng.uniform(26, 34), 1);
            glances.add(new Glance(start, duration, forward));
            t += d + rng.uniform(6.0, 10.0);
        }
        return new ScenarioSpec("brief_glances_down",
                "Calibrate, then repeated 3-5 s glances down to ~30 deg (e.g. at a phone) "
                        + "separated by 6-10 s of neutral. Expect deviations but no reminders/episodes.",
                seed, 72.0)
                .sampleRateHz(20.0)
                .actions(new ArrayList<>(CALIBRATE_AT_START))
                .glances(glances)
                .expected(s -> expected(List.of("succeeded"), List.of(), "neutral"));
    }

    public static ScenarioSpec lateralRightTilt() {
        return lateralRightTilt(104);
    }

    public static ScenarioSpec lateralRightTilt(long seed) {
        return new ScenarioSpec("lateral_right_tilt",
                "Starts at t=5000 s (non-zero clock). Calibrate, tilt right ear toward right "
                        + "shoulder to 20 deg over 3 s, hold 45 s, return. Expect one 'right' reminder.",
                seed, 72.0)
                .startTimestamp(5000.0)
                .actions(new ArrayList<>(CALIBRATE_AT_START))
                .keyframes(keyframes(new double[][] {{0, 0, 0}, {15, 0, 0}, {18, 0, 20}, {63, 0, 20}, {66, 0, 0}}))
                .expected(s -> expected(List.of("succeeded"),
                        List.of(episode(s, TiltDirection.RIGHT, 11, true)), "neutral"));
    }

    public static ScenarioSpec cooldownRetrigger() {
        return cooldownRetrigger(105);
    }

    public static ScenarioSpec cooldownRetrigger(long seed) {
        ObjectNode config = axesConfig();
        config.put("sustainedDuration", 10.0);
        config.put("reminderCooldown", 60.0);
        return new ScenarioSpec("cooldown_retrigger",
                "sustainedDuration 10 s, reminderCooldown 60 s. Three 22 deg forward tilts: the "
                        + "first reminds; the second becomes sustained inside the cooldown (no reminder); "
                        + "the third becomes sustained after the cooldown (reminds).",
                seed, 116.0)
                .sampleRateHz(20.0)
                .actions(new ArrayList<>(CALIBRATE_AT_START))
                .config(config)
                .keyframes(keyframes(new double[][] {{0, 0, 0}, {14, 0, 0}, {16, 22, 0}, {34, 22, 0}, {36, 0, 0},
                        {40, 0, 0}, {42, 22, 0}, {58, 22, 0}, {60, 0, 0},
                        {88, 0, 0}, {90, 22, 0}, {106, 22, 0}, {108, 0, 0}}))
                .expected(s -> expected(List.of("succeeded"), List.of(
                        episode(s, TiltDirection.FORWARD, 11, true),
                        episode(s, TiltDirection.FORWARD, 37, false),
                        episode(s, TiltDirection.FORWARD, 61, true)), "neutral"));
    }

    public static ScenarioSpec calibrationTooMuchMovement() {
        return calibrationTooMuchMovement(106);
    }

    public static ScenarioSpec calibrationTooMuchMovement(long seed) {
        return new ScenarioSpec("calibration_too_much_movement",
                "The user nods/looks around (+-9 deg forward, +-4 deg lateral) during the 10 s "
                        + "calibration. Expect calibration to fail with tooMuchMovement.",
                seed, 15.0)
                .actions(new ArrayList<>(CALIBRATE_AT_START))
                .wobble(t -> t <= 10.5
                        ? new Angles(9.0 * StrictMath.sin(2 * Math.PI * 0.3 * t), 4.0 * StrictMath.sin(2 * Math.PI * 0.2 * t))
                        : new Angles(0.0, 0.0))
                .expected(s -> expected(List.of("tooMuchMovement"), List.of(), "needsCalibration"));
    }

    public static ScenarioSpec disconnectMidTilt() {
        return disconnectMidTilt(107);
    }

    public static ScenarioSpec disconnectMidTilt(long seed) {
        Interval gap = new Interval(52.0, 57.0);
        double lastBeforeGap = 52.0 - 1.0 / 25.0;
        return new ScenarioSpec("disconnect_mid_tilt",
                "Calibrate, tilt 22 deg forward from 14 s (reminder ~46 s), then no samples for "
                        + "5 s from 52 s (AirPods disconnected). The gap closes the episode at the last "
                        + "sample before it; after reconnecting the head returns to neutral at 66-68 s.",
                seed, 72.0)
                .actions(new ArrayList<>(CALIBRATE_AT_START))
                .gaps(List.of(gap))
                .keyframes(keyframes(new double[][] {{0, 0, 0}, {14, 0, 0}, {17, 22, 0}, {66, 22, 0}, {68, 0, 0}}))
                .expected(s -> expected(List.of("succeeded"), List.of(
                        episode(s, TiltDirection.FORWARD, 11, true, PythonFormat.round(lastBeforeGap, 4))),
                        "neutral"));
    }

    public static ScenarioSpec lookingUpBackward() {
        return lookingUpBackward(108);
    }

    public static ScenarioSpec lookingUpBackward(long seed) {
        return new ScenarioSpec("looking_up_backward",
                "Calibrate, look up 30 deg (e.g. at a high monitor) over 3 s, hold 42 s, return. "
                        + "Expect one 'backward' reminder (backward threshold 20 deg).",
                seed, 68.0)
                .actions(new ArrayList<>(CALIBRATE_AT_START))
                .keyframes(keyframes(new double[][] {{0, 0, 0}, {15, 0, 0}, {18, -30, 0}, {60, -30, 0}, {63, 0, 0}}))
                .expected(s -> expected(List.of("succeeded"),
                        List.of(episode(s, TiltDirection.BACKWARD, 11, true)), "neutral"));
    }

    /** Every scenario with its default seed, in file-writing order. */
    public static final Map<String, Supplier<ScenarioSpec>> SCENARIOS = scenarios();

    private static Map<String, Supplier<ScenarioSpec>> scenarios() {
        Map<String, Supplier<ScenarioSpec>> m = new LinkedHashMap<>();
        m.put("steady_neutral", Generator::steadyNeutral);
        m.put("gradual_forward_slouch", Generator::gradualForwardSlouch);
        m.put("brief_glances_down", Generator::briefGlancesDown);
        m.put("lateral_right_tilt", Generator::lateralRightTilt);
        m.put("cooldown_retrigger", Generator::cooldownRetrigger);
        m.put("calibration_too_much_movement", Generator::calibrationTooMuchMovement);
        m.put("disconnect_mid_tilt", Generator::disconnectMidTilt);
        m.put("looking_up_backward", Generator::lookingUpBackward);
        return Collections.unmodifiableMap(m);
    }

    // MARK: - Writing

    /**
     * Replays the (already rounded) fixture through the reference pipeline and stores the exact
     * output as {@code reference}, placed before {@code samples}.
     */
    public static ObjectNode withReference(ObjectNode fixture) {
        Fixtures.ReplayResult result = Fixtures.replay(fixture);
        ObjectNode ordered = Json.object();
        for (Map.Entry<String, JsonNode> e : fixture.properties()) {
            if (!e.getKey().equals("samples")) {
                ordered.set(e.getKey(), e.getValue());
            }
        }
        ordered.set("reference", Fixtures.referenceBlock(result));
        ordered.set("samples", fixture.get("samples"));
        return ordered;
    }

    /** The fixture file layout: indented header, then one compact line per sample. */
    public static String dumpsFixture(ObjectNode fixture) {
        ObjectNode header = fixture.deepCopy();
        header.remove("samples");
        String head = Json.dumps(header, 2);
        if (!head.endsWith("}")) {
            throw new IllegalStateException("unexpected header layout");
        }
        List<String> rows = new ArrayList<>();
        for (JsonNode s : fixture.get("samples")) {
            rows.add(Json.dumpsCompact(s));
        }
        return head.substring(0, head.length() - 1).stripTrailing()
                + ",\n  \"samples\": [\n" + String.join(",\n", rows) + "\n  ]\n}\n";
    }

    /** Writes every scenario to {@code directory}/{name}.json and returns the paths. */
    public static List<Path> writeAll(Path directory) {
        try {
            Files.createDirectories(directory);
            List<Path> written = new ArrayList<>();
            for (Map.Entry<String, Supplier<ScenarioSpec>> e : SCENARIOS.entrySet()) {
                ObjectNode fixture = synthesize(e.getValue().get()).fixture();
                // Round-trip through JSON so the reference is computed on exactly what is stored.
                fixture = (ObjectNode) Json.parse(Json.dumpsCompact(fixture));
                fixture = withReference(fixture);
                Path path = directory.resolve(e.getKey() + ".json");
                Files.writeString(path, dumpsFixture(fixture), StandardCharsets.UTF_8);
                written.add(path);
            }
            return written;
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /** {@code [--out <dir>]}; the default is the shared fixture directory. */
    public static void main(String[] args) throws IOException {
        Path out = null;
        for (int i = 0; i < args.length; i++) {
            switch (args[i]) {
                case "--out" -> out = Path.of(args[++i]);
                case "-h", "--help" -> {
                    System.out.println("usage: Generator [--out <dir>]   (default: " + Fixtures.FIXTURE_SUBDIR + ")");
                    return;
                }
                default -> throw new IllegalArgumentException("unknown argument: " + args[i]);
            }
        }
        if (out == null) {
            out = Fixtures.fixtureDir();
        }
        long total = 0;
        for (Path p : writeAll(out)) {
            long size = Files.size(p);
            total += size;
            System.out.printf(Locale.ROOT, "%-40s %7.1f KiB%n", p.getFileName(), size / 1024.0);
        }
        System.out.printf(Locale.ROOT, "%-40s %7.1f KiB%n", "total", total / 1024.0);
    }
}
