package com.bachnguyennn.align.reference;

import static com.bachnguyennn.align.reference.Geometry.gravityInHeadFrame;

import com.bachnguyennn.align.reference.Fixtures.ReplayResult;
import com.bachnguyennn.align.reference.Geometry.Vec3;
import com.bachnguyennn.align.reference.ScenarioSpec.Glance;
import com.bachnguyennn.align.reference.ScenarioSpec.Keyframe;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Consumer;
import java.util.function.LongFunction;
import java.util.stream.Collectors;

/**
 * Evaluation of the reference posture pipeline on synthetic data (A-04).
 *
 * <p>Run from analytics/align-tools:
 * <pre>
 *   ./mvnw -q compile exec:java@evaluate                              # writes results/evaluation.md
 *   ./mvnw -q compile exec:java@evaluate -Dexec.args="--seeds 5 --out /tmp/eval.md"
 * </pre>
 * Options: {@code --seeds N} (default 20), {@code --out PATH} (default
 * analytics/align-tools/results/evaluation.md).
 *
 * <p>Every number is produced by replaying freshly synthesized scenarios ({@link Generator}
 * motion model) through {@link PostureMonitor}. Synthetic data cannot validate real-world accuracy;
 * it measures the algorithm's timing behaviour and robustness to the modelled noise. Because the
 * Java generator draws different random numbers than numpy, every table except the noise-free axis
 * projection differs slightly from the Python report (analytics/experiments/results/evaluation.md).
 */
public final class Evaluate {

    public static final String DEFAULT_OUT = "analytics/align-tools/results/evaluation.md";

    private Evaluate() {}

    // MARK: - Helpers

    public static ObjectNode build(ScenarioSpec spec) {
        return Generator.synthesize(spec).fixture();
    }

    public static PostureConfiguration configFor(ScenarioSpec spec) {
        return PostureConfiguration.fromOverrides(spec.config());
    }

    public static PostureConfiguration configFor(ScenarioSpec spec, Consumer<PostureConfiguration.Builder> changes) {
        return configFor(spec).replacing(changes);
    }

    public static int deviatingEntries(ReplayResult result) {
        int count = 0;
        PostureState.Kind previous = null;
        for (PostureUpdate u : result.updates()) {
            if (u.state().kind() == PostureState.Kind.DEVIATING && previous != PostureState.Kind.DEVIATING) {
                count++;
            }
            previous = u.state().kind();
        }
        return count;
    }

    /** Python {@code fmt}: fixed digits, "n/a" for null or NaN. */
    public static String fmt(Double x, int digits) {
        if (x == null || x.isNaN()) {
            return "n/a";
        }
        return PythonFormat.fixed(x, digits);
    }

    public static String fmt(Double x) {
        return fmt(x, 2);
    }

    public static String table(List<String> headers, List<List<String>> rows) {
        List<String> out = new ArrayList<>();
        out.add("| " + String.join(" | ", headers) + " |");
        out.add("|" + headers.stream().map(h -> "---").collect(Collectors.joining("|")) + "|");
        for (List<String> r : rows) {
            out.add("| " + String.join(" | ", r) + " |");
        }
        return String.join("\n", out);
    }

    /** "mean (min a, max b)" with 2 decimals, or "n/a". */
    public static String stats(List<Double> values) {
        if (values.isEmpty()) {
            return "n/a";
        }
        double sum = 0.0;
        double min = Double.POSITIVE_INFINITY;
        double max = Double.NEGATIVE_INFINITY;
        for (double v : values) {
            sum += v;
            min = Math.min(min, v);
            max = Math.max(max, v);
        }
        return PythonFormat.fixed(sum / values.size(), 2) + " (min " + PythonFormat.fixed(min, 2)
                + ", max " + PythonFormat.fixed(max, 2) + ")";
    }

    private static double mean(List<Integer> values) {
        return values.stream().mapToInt(Integer::intValue).average().orElse(Double.NaN);
    }

    /** Calibrate, neutral to 12 s, 3 s ramp to the pose, hold, 3 s ramp back, 7 s neutral. */
    public static ScenarioSpec holdSpec(long seed, double forward, double lateral, double hold) {
        double endHold = 15.0 + hold;
        return new ScenarioSpec("hold", "", seed, endHold + 10.0)
                .actions(new ArrayList<>(Generator.CALIBRATE_AT_START))
                .keyframes(List.of(new Keyframe(0, 0, 0), new Keyframe(12, 0, 0), new Keyframe(15, forward, lateral),
                        new Keyframe(endHold, forward, lateral), new Keyframe(endHold + 3, 0, 0)));
    }

    public static ScenarioSpec glanceSpec(long seed, double duration) {
        return glanceSpec(seed, duration, 30.0);
    }

    public static ScenarioSpec glanceSpec(long seed, double duration, double depth) {
        return new ScenarioSpec("glance", "", seed, 20.0 + duration + 10.0)
                .actions(new ArrayList<>(Generator.CALIBRATE_AT_START))
                .glances(List.of(new Glance(15.0, duration, depth, 0.0, 0.4)));
    }

    private static String ratio(int hits, int total) {
        return hits + "/" + total;
    }

    // MARK: - Experiments

    private record LatencyCase(String name, LongFunction<ScenarioSpec> builder, TiltDirection direction,
                               double onsetRel) {}

    public static String latency(int seeds) {
        List<List<String>> rows = new ArrayList<>();
        List<LatencyCase> cases = List.of(
                new LatencyCase("gradual_forward_slouch", Generator::gradualForwardSlouch, TiltDirection.FORWARD, 20.0),
                new LatencyCase("lateral_right_tilt", Generator::lateralRightTilt, TiltDirection.RIGHT, 15.0),
                new LatencyCase("looking_up_backward", Generator::lookingUpBackward, TiltDirection.BACKWARD, 15.0));
        for (LatencyCase c : cases) {
            List<Double> fromCross = new ArrayList<>();
            List<Double> fromOnset = new ArrayList<>();
            List<Double> extra = new ArrayList<>();
            int detected = 0;
            for (int k = 0; k < seeds; k++) {
                ScenarioSpec spec = c.builder().apply(1000 + k);
                ReplayResult res = Fixtures.replay(build(spec));
                PostureConfiguration cfg = configFor(spec);
                double crossRel = Generator.truthEpisode(spec, c.direction(), 11.0).onset();
                double cross = spec.startTimestamp() + crossRel;
                double onset = spec.startTimestamp() + c.onsetRel();
                List<ReminderDecision> r = res.reminders().stream().filter(x -> x.direction() == c.direction()).toList();
                if (res.reminders().size() == 1 && !r.isEmpty()) {
                    detected++;
                    fromCross.add(r.get(0).timestamp() - cross);
                    fromOnset.add(r.get(0).timestamp() - onset);
                    extra.add(r.get(0).timestamp() - cross - cfg.sustainedDuration());
                }
            }
            rows.add(List.of(c.name(), ratio(detected, seeds), stats(fromOnset), stats(fromCross), stats(extra)));
        }
        return table(List.of("scenario", "exactly 1 reminder", "reminder − tilt onset (s)",
                "reminder − truth threshold crossing (s)", "delay beyond sustainedDuration (s)"), rows);
    }

    public static String falsePositives(int seeds) {
        List<List<String>> rows = new ArrayList<>();
        Map<String, LongFunction<ScenarioSpec>> builders = new LinkedHashMap<>();
        builders.put("steady_neutral", Generator::steadyNeutral);
        builders.put("brief_glances_down", Generator::briefGlancesDown);
        for (Map.Entry<String, LongFunction<ScenarioSpec>> b : builders.entrySet()) {
            int reminders = 0;
            int episodes = 0;
            List<Double> entries = new ArrayList<>();
            double minutes = 0.0;
            for (int k = 0; k < seeds; k++) {
                ScenarioSpec spec = b.getValue().apply(2000 + k);
                ReplayResult res = Fixtures.replay(build(spec), null, true);
                reminders += res.reminders().size();
                episodes += res.episodes().size();
                double mins = (spec.duration() - 10.0) / 60.0;
                minutes += mins;
                entries.add(deviatingEntries(res) / mins);
            }
            rows.add(List.of(b.getKey(), String.valueOf(seeds), PythonFormat.fixed(minutes, 1),
                    String.valueOf(reminders), String.valueOf(episodes), stats(entries)));
        }
        return table(List.of("scenario", "runs", "monitored minutes", "reminders", "episodes",
                "entries into `deviating` per minute"), rows);
    }

    public static String glanceDurationSweep(int seeds) {
        List<List<String>> rows = new ArrayList<>();
        for (double duration : new double[] {5.0, 10.0, 20.0, 29.0, 31.0, 32.0, 40.0}) {
            int reminded = 0;
            for (int k = 0; k < seeds; k++) {
                ReplayResult res = Fixtures.replay(build(glanceSpec(3000 + k, duration)));
                reminded += res.reminders().isEmpty() ? 0 : 1;
            }
            rows.add(List.of(PythonFormat.fixed(duration, 0), ratio(reminded, seeds)));
        }
        return table(List.of("30° glance length incl. 0.4 s ramps (s)", "runs with a reminder"), rows);
    }

    /** Head held near the forward threshold: flicker vs hysteresis and smoothing. */
    public static String hoverSweep(int seeds) {
        List<List<String>> rows = new ArrayList<>();
        for (double hysteresis : new double[] {0.0, 1.0, 3.0, 5.0}) {
            for (double tau : new double[] {0.0, 0.5, 2.0}) {
                for (double offset : new double[] {-1.0, 0.0, 1.0}) {
                    List<Integer> entries = new ArrayList<>();
                    List<Integer> eps = new ArrayList<>();
                    for (int k = 0; k < seeds; k++) {
                        ScenarioSpec spec = holdSpec(4000 + k, 15.0 + offset, 0.0, 60.0);
                        PostureConfiguration cfg = configFor(spec,
                                b -> b.hysteresisDegrees(hysteresis).smoothingTimeConstant(tau));
                        ReplayResult res = Fixtures.replay(build(spec), cfg, true);
                        entries.add(deviatingEntries(res));
                        eps.add(res.episodes().size());
                    }
                    int maxEntries = entries.stream().mapToInt(Integer::intValue).max().orElse(0);
                    rows.add(List.of(fmt(hysteresis, 0), fmt(tau, 1), PythonFormat.fixed(15 + offset, 0),
                            fmt(mean(entries), 1), String.valueOf(maxEntries), fmt(mean(eps), 2)));
                }
            }
        }
        return table(List.of("hysteresis (°)", "tau (s)", "held angle (°, threshold 15)",
                "mean entries into deviating / 60 s hold", "max entries", "mean sustained episodes"), rows);
    }

    public static String thresholdSweep(int seeds) {
        List<List<String>> rows = new ArrayList<>();
        double[] angles = {12.0, 15.0, 18.0, 20.0, 25.0};
        for (double threshold : new double[] {10.0, 12.0, 15.0, 18.0, 20.0}) {
            List<String> row = new ArrayList<>();
            row.add(fmt(threshold, 0));
            for (double angle : angles) {
                int hits = 0;
                for (int k = 0; k < seeds; k++) {
                    ScenarioSpec spec = holdSpec(5000 + k, angle, 0.0, 45.0);
                    ReplayResult res = Fixtures.replay(build(spec),
                            configFor(spec, b -> b.forwardThresholdDegrees(threshold)));
                    hits += res.reminders().isEmpty() ? 0 : 1;
                }
                row.add(ratio(hits, seeds));
            }
            int fp = 0;
            for (int k = 0; k < seeds; k++) {
                ScenarioSpec spec = Generator.steadyNeutral(6000 + k).swayDeg(1.0).microInterval(4.0);
                ReplayResult res = Fixtures.replay(build(spec), configFor(spec, b -> b.forwardThresholdDegrees(threshold)));
                fp += res.reminders().size();
            }
            row.add(String.valueOf(fp));
            rows.add(row);
        }
        List<String> headers = new ArrayList<>();
        headers.add("forward threshold (°)");
        for (double a : angles) {
            headers.add("45 s hold at " + PythonFormat.fixed(a, 0) + "°");
        }
        headers.add("reminders on noisy neutral (sway 1°, micro every 4 s)");
        return table(headers, rows);
    }

    public static String tauSweep(int seeds) {
        List<List<String>> rows = new ArrayList<>();
        for (double tau : new double[] {0.0, 0.25, 0.5, 1.0, 2.0}) {
            List<Double> lat = new ArrayList<>();
            for (int k = 0; k < seeds; k++) {
                ScenarioSpec spec = Generator.gradualForwardSlouch(7000 + k);
                ReplayResult res = Fixtures.replay(build(spec), configFor(spec, b -> b.smoothingTimeConstant(tau)));
                double crossRel = Generator.truthEpisode(spec, TiltDirection.FORWARD, 11.0).onset();
                if (res.reminders().size() == 1) {
                    lat.add(res.reminders().get(0).timestamp() - crossRel - 30.0);
                }
            }
            List<Integer> glanceEntries = new ArrayList<>();
            for (int k = 0; k < seeds; k++) {
                ScenarioSpec spec = Generator.briefGlancesDown(7500 + k);
                ReplayResult res = Fixtures.replay(build(spec), configFor(spec, b -> b.smoothingTimeConstant(tau)), true);
                glanceEntries.add(deviatingEntries(res));
            }
            rows.add(List.of(fmt(tau, 2), ratio(lat.size(), seeds), stats(lat), fmt(mean(glanceEntries), 1)));
        }
        return table(List.of("tau (s)", "slouch detected", "delay beyond crossing + 30 s (s)",
                "mean deviating entries, glance scenario"), rows);
    }

    public static String calibrationNoise(int seeds) {
        List<List<String>> rows = new ArrayList<>();
        for (double sway : new double[] {0.5, 1.0, 1.5, 2.0, 3.0}) {
            int ok = 0;
            for (int k = 0; k < seeds; k++) {
                ScenarioSpec spec = Generator.steadyNeutral(8000 + k).swayDeg(sway).duration(12.0);
                ReplayResult res = Fixtures.replay(build(spec));
                ok += res.calibrationOutcomes().equals(List.of("succeeded")) ? 1 : 0;
            }
            rows.add(List.of(fmt(sway, 1), ratio(ok, seeds)));
        }
        return table(List.of("sway std (°) during calibration", "calibrations succeeded (spread limit 5°)"), rows);
    }

    /** Noise-free, so identical to the Python report. */
    public static String axisProjection() {
        List<List<String>> rows = new ArrayList<>();
        HeadAxisConvention axes = PostureConfiguration.DEFAULT.axes();
        int[][] mounts = {{0, 0}, {10, 0}, {20, 0}, {0, 10}, {10, -5}, {20, 10}};
        for (int[] m : mounts) {
            int pitch = m[0];
            int roll = m[1];
            Vec3 g0 = gravityInHeadFrame(Pose.poseAttitude(0, 0, 0, pitch, roll));
            List<String> row = new ArrayList<>();
            row.add(pitch + "/" + roll);
            for (boolean ortho : new boolean[] {true, false}) {
                Vec3 gF = gravityInHeadFrame(Pose.poseAttitude(20, 0, 0, pitch, roll));
                Vec3 gL = gravityInHeadFrame(Pose.poseAttitude(0, 20, 0, pitch, roll));
                TiltEstimate tf = Tilt.estimateTilt(0, gF, g0, axes, ortho);
                TiltEstimate tl = Tilt.estimateTilt(0, gL, g0, axes, ortho);
                for (double v : new double[] {tf.forwardDegrees() - 20, tl.lateralDegrees() - 20,
                        tf.lateralDegrees(), tl.forwardDegrees()}) {
                    row.add(fmt(v, 3));
                }
            }
            rows.add(row);
        }
        return table(List.of("mount pitch/roll (°)", "baseline-plane: fwd err", "lat err", "fwd→lat crosstalk",
                "lat→fwd crosstalk", "plain: fwd err", "lat err", "fwd→lat crosstalk", "lat→fwd crosstalk"), rows);
    }

    public static String decimation(int seeds) {
        List<List<String>> rows = new ArrayList<>();
        for (Double rate : new Double[] {null, 15.0, 10.0, 5.0}) {
            List<Double> lat = new ArrayList<>();
            int okCal = 0;
            for (int k = 0; k < seeds; k++) {
                ScenarioSpec spec = Generator.gradualForwardSlouch(9000 + k);
                ReplayResult res = Fixtures.replay(build(spec), configFor(spec,
                        b -> b.maxProcessingRateHz(rate).minimumCalibrationSamples(40)));
                okCal += res.calibrationOutcomes().equals(List.of("succeeded")) ? 1 : 0;
                double crossRel = Generator.truthEpisode(spec, TiltDirection.FORWARD, 11.0).onset();
                if (res.reminders().size() == 1) {
                    lat.add(res.reminders().get(0).timestamp() - crossRel - 30.0);
                }
            }
            rows.add(List.of(rate == null ? "none (25 Hz)" : PythonFormat.fixed(rate, 0) + " Hz",
                    ratio(okCal, seeds), ratio(lat.size(), seeds), stats(lat)));
        }
        return table(List.of("maxProcessingRateHz", "calibration ok (min samples 40)", "slouch detected",
                "delay beyond crossing + 30 s (s)"), rows);
    }

    public static String throughput() {
        ScenarioSpec spec = Generator.gradualForwardSlouch(1);
        ObjectNode fx = build(spec);
        int n = fx.get("samples").size();
        List<MotionSample> samples = Fixtures.fixtureSamples(fx);
        long start = System.nanoTime();
        Fixtures.replay(fx, null, false, true, samples);
        double elapsed = (System.nanoTime() - start) / 1e9;
        return "Java reference: " + n + " samples in " + PythonFormat.fixed(elapsed * 1000, 0) + " ms ("
                + PythonFormat.fixed(elapsed / n * 1e6, 1) + " µs/sample, HotSpot JVM after the runs above, "
                + "informational only).";
    }

    // MARK: - Main

    public static String report(int seeds) {
        long t0 = System.nanoTime();
        int small = Math.max(5, seeds / 2);
        Map<String, String> sections = new LinkedHashMap<>();
        sections.put("Detection latency (default configuration)", latency(seeds));
        sections.put("False positives and flicker on non-slouch scenarios", falsePositives(seeds));
        sections.put("Glance length vs reminder (sustainedDuration 30 s)", glanceDurationSweep(seeds));
        sections.put("Flicker near threshold: hysteresis x smoothing", hoverSweep(small));
        sections.put("Threshold sensitivity", thresholdSweep(small));
        sections.put("Smoothing time constant sensitivity", tauSweep(seeds));
        sections.put("Calibration robustness to sway", calibrationNoise(seeds));
        sections.put("Axis projection with earbud mounting offset (noise-free, 20° poses)", axisProjection());
        sections.put("Decimation", decimation(small));
        sections.put("Throughput", throughput());
        String header = "# Align reference evaluation output\n\nGenerated by `./mvnw -q compile exec:java@evaluate "
                + "-Dexec.args=\"--seeds " + seeds + "\"` (Java " + System.getProperty("java.version") + "). "
                + "Seeds per cell: " + seeds + " unless noted (sweeps marked with a hold/hover use " + small + ").\n\n"
                + "All synthetic data comes from the Java generator (`Generator.java`, SplittableRandom), not numpy, so "
                + "every table except the noise-free axis projection differs slightly from the Python report "
                + "(`analytics/experiments/results/evaluation.md`); the axis projection table is identical.\n";
        String body = sections.entrySet().stream()
                .map(e -> "## " + e.getKey() + "\n\n" + e.getValue())
                .collect(Collectors.joining("\n\n"));
        double total = (System.nanoTime() - t0) / 1e9;
        return header + "\n" + body + "\n\nTotal runtime: " + PythonFormat.fixed(total, 0) + " s.\n";
    }

    public static void main(String[] args) throws IOException {
        int seeds = 20;
        Path out = null;
        for (int i = 0; i < args.length; i++) {
            switch (args[i]) {
                case "--seeds" -> seeds = Integer.parseInt(args[++i]);
                case "--out" -> out = Path.of(args[++i]);
                case "-h", "--help" -> {
                    System.out.println("usage: Evaluate [--seeds N] [--out PATH]   (default: 20, " + DEFAULT_OUT + ")");
                    return;
                }
                default -> throw new IllegalArgumentException("unknown argument: " + args[i]);
            }
        }
        if (out == null) {
            out = Fixtures.repoRoot().resolve(DEFAULT_OUT);
        }
        String text = report(seeds);
        Path parent = out.toAbsolutePath().getParent();
        if (parent != null) {
            Files.createDirectories(parent);
        }
        Files.writeString(out, text, StandardCharsets.UTF_8);
        System.out.print(text);
    }
}
