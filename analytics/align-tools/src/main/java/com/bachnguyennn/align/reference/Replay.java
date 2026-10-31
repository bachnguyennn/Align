package com.bachnguyennn.align.reference;

import com.bachnguyennn.align.reference.Fixtures.ReplayResult;
import com.bachnguyennn.align.reference.Geometry.Vec3;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.io.PrintStream;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Replays motion recordings (or fixtures) through the reference pipeline and prints a readable
 * timeline summary (D-017 (d): tuning on real data). Recording format: shared/fixtures/README.md.
 *
 * <p>Run from analytics/align-tools:
 * <pre>
 *   ./mvnw -q compile exec:java@replay -Dexec.args="../../shared/fixtures/motion/gradual_forward_slouch.json"
 *   ./mvnw -q compile exec:java@replay -Dexec.args="--set forwardThresholdDegrees=12 --set axisCalibrationMaxYawDegrees=30 rec1.json rec2.json"
 * </pre>
 * {@code --set key=value} (repeatable) overrides a configuration value on top of the file's own
 * {@code config}; keys are the fixture configuration keys (Swift property names), values are JSON
 * ({@code 12}, {@code null}, {@code [-1,0,0]}). Relative paths are resolved against the working
 * directory, then against the repository root.
 */
public final class Replay {

    private Replay() {}

    /** Parses {@code key=value} into a fixture-style override node (value parsed as JSON). */
    public static ObjectNode parseOverride(String assignment, ObjectNode into) {
        int eq = assignment.indexOf('=');
        if (eq <= 0) {
            throw new IllegalArgumentException("--set expects key=value, got: " + assignment);
        }
        String key = assignment.substring(0, eq).trim();
        String value = assignment.substring(eq + 1).trim();
        if (!PostureConfiguration.isKey(key)) {
            throw new IllegalArgumentException("unknown configuration key: " + key);
        }
        into.set(key, Json.parse(value));
        return into;
    }

    /** The configuration a file is replayed with: its {@code config}, then {@code overrides}. */
    public static PostureConfiguration configuration(JsonNode fx, JsonNode overrides) {
        return PostureConfiguration.fromOverrides(fx.get("config")).withOverrides(overrides);
    }

    /** Nearest-rank percentile of a sorted array (p in [0, 100]); NaN when empty. */
    public static double percentile(double[] sorted, double p) {
        if (sorted.length == 0) {
            return Double.NaN;
        }
        int rank = (int) Math.ceil(p / 100.0 * sorted.length);
        int index = Math.min(sorted.length - 1, Math.max(0, rank - 1));
        return sorted[index];
    }

    private static String f(double x, int digits) {
        return Evaluate.fmt(x, digits);
    }

    private static String signed(double x, int digits) {
        String s = f(x, digits);
        return x >= 0 && !s.startsWith("-") ? "+" + s : s;
    }

    private static String vec(Vec3 v) {
        return "(" + f(v.x(), 4) + ", " + f(v.y(), 4) + ", " + f(v.z(), 4) + ")";
    }

    /** A readable summary of replaying {@code fx} with {@code overrides} (may be null). */
    public static String summarize(String label, JsonNode fx, JsonNode overrides) {
        PostureConfiguration config = configuration(fx, overrides);
        ReplayResult result = Fixtures.replay(fx, config, true);
        List<MotionSample> samples = Fixtures.fixtureSamples(fx);
        StringBuilder out = new StringBuilder();
        String kind = fx.has("recording") ? "recording" : fx.has("expected") ? "fixture" : "file";
        out.append("== ").append(label).append(" (").append(kind).append(", name ")
                .append(fx.path("name").asText("?")).append(") ==\n");

        JsonNode rec = fx.get("recording");
        if (rec != null && rec.isObject()) {
            for (String key : List.of("createdAt", "appVersion", "device", "headphones", "notes")) {
                if (rec.hasNonNull(key)) {
                    out.append("  ").append(key).append(": ").append(rec.get(key).asText()).append('\n');
                }
            }
        }
        if (overrides != null && !overrides.isEmpty()) {
            out.append("  overrides: ").append(Json.dumpsCompact(overrides)).append('\n');
        }

        // Samples, rate and gaps.
        if (samples.isEmpty()) {
            out.append("  no samples\n");
            return out.toString();
        }
        double first = samples.get(0).timestamp();
        double last = samples.get(samples.size() - 1).timestamp();
        double largestGap = 0.0;
        double gapAt = first;
        double[] dts = new double[Math.max(0, samples.size() - 1)];
        for (int i = 1; i < samples.size(); i++) {
            double dt = samples.get(i).timestamp() - samples.get(i - 1).timestamp();
            dts[i - 1] = dt;
            if (dt > largestGap) {
                largestGap = dt;
                gapAt = samples.get(i - 1).timestamp();
            }
        }
        double[] sortedDts = dts.clone();
        Arrays.sort(sortedDts);
        double medianDt = percentile(sortedDts, 50);
        double span = last - first;
        out.append("  samples: ").append(samples.size()).append(" over ").append(f(span, 1)).append(" s (t ")
                .append(f(first, 2)).append(" .. ").append(f(last, 2)).append("); nominal ")
                .append(f(fx.path("sampleRateHz").asDouble(Double.NaN), 1)).append(" Hz, mean ")
                .append(f(span > 0 ? (samples.size() - 1) / span : Double.NaN, 1)).append(" Hz, median interval ")
                .append(f(medianDt * 1000, 1)).append(" ms; largest gap ").append(f(largestGap, 3))
                .append(" s after t ").append(f(gapAt, 2))
                .append(largestGap > config.maxSampleGap() ? " (> maxSampleGap: acts as an interrupt)" : "")
                .append('\n');

        // Learned axes.
        HeadAxisConvention learned = result.learnedAxes();
        if (learned != null) {
            out.append("  learned axes: forward ").append(vec(learned.forwardAxis())).append(", lateral ")
                    .append(vec(learned.lateralAxis())).append("; yaw ").append(signed(result.learnedYawDegrees(), 2))
                    .append(" deg from the configured forward axis ").append(vec(config.axes().forwardAxis()))
                    .append('\n');
        } else {
            out.append("  learned axes: none (configured axes ").append(vec(config.axes().forwardAxis())).append(" / ")
                    .append(vec(config.axes().lateralAxis())).append(")\n");
        }
        if (result.finalBaseline() != null) {
            out.append("  baseline: gravity ").append(vec(result.finalBaseline().gravity())).append(", version ")
                    .append(result.finalBaseline().version()).append('\n');
        }

        // Tilt percentiles over monitored (non-calibrating) updates.
        List<Double> fwd = new ArrayList<>();
        List<Double> lat = new ArrayList<>();
        List<Double> tot = new ArrayList<>();
        for (PostureUpdate u : result.updates()) {
            if (u.tilt() != null && u.state().kind() != PostureState.Kind.CALIBRATING) {
                fwd.add(u.tilt().forwardDegrees());
                lat.add(u.tilt().lateralDegrees());
                tot.add(u.tilt().totalDegrees());
            }
        }
        out.append("  tilt while monitoring (deg, ").append(fwd.size()).append(" updates): p5 / p50 / p95 / min / max\n");
        Map<String, List<Double>> series = new LinkedHashMap<>();
        series.put("forward", fwd);
        series.put("lateral", lat);
        series.put("total", tot);
        for (Map.Entry<String, List<Double>> e : series.entrySet()) {
            double[] v = e.getValue().stream().mapToDouble(Double::doubleValue).sorted().toArray();
            out.append("    ").append(String.format("%-8s", e.getKey()));
            if (v.length == 0) {
                out.append("n/a\n");
                continue;
            }
            out.append(signed(percentile(v, 5), 2)).append(" / ").append(signed(percentile(v, 50), 2)).append(" / ")
                    .append(signed(percentile(v, 95), 2)).append(" / ").append(signed(v[0], 2)).append(" / ")
                    .append(signed(v[v.length - 1], 2)).append('\n');
        }

        // Timeline.
        out.append("  timeline:\n");
        PostureState.Kind previous = null;
        Map<TiltDirection, Integer> deviations = new LinkedHashMap<>();
        Double previousT = null;
        for (PostureUpdate u : result.updates()) {
            String t = String.format("    t %9s  ", f(u.timestamp(), 2));
            PostureState.Kind k = u.state().kind();
            if (previousT != null && u.timestamp() - previousT > config.maxSampleGap()) {
                out.append(t).append("after a ").append(f(u.timestamp() - previousT, 2))
                        .append(" s gap (interrupt at t ").append(f(previousT, 2)).append(")\n");
            }
            previousT = u.timestamp();
            if (u.calibrationOutcome() != null) {
                out.append(t).append("neutral calibration ").append(u.calibrationOutcome().name()).append('\n');
            }
            if (u.axisCalibrationOutcome() != null) {
                AxisCalibrationOutcome o = u.axisCalibrationOutcome();
                out.append(t).append("axis calibration ").append(o.name());
                if (o.succeeded() && result.finalBaseline() != null) {
                    out.append(" (yaw ").append(signed(AxisCalibrationService.signedYawDegrees(
                            o.axes().forwardAxis(), result.finalBaseline().gravity(), config.axes()), 2)).append(" deg)");
                }
                out.append('\n');
            }
            if (u.completedEpisode() != null) {
                PostureEpisode e = u.completedEpisode();
                out.append(t).append("episode ").append(e.direction()).append(" ").append(f(e.startTimestamp(), 2))
                        .append(" .. ").append(f(e.endTimestamp(), 2)).append(" (")
                        .append(f(e.endTimestamp() - e.startTimestamp(), 1)).append(" s, peak ")
                        .append(f(e.peakDeviationDegrees(), 1)).append(" deg, reminded ").append(e.reminderTriggered())
                        .append(")\n");
            }
            if (k != previous) {
                switch (k) {
                    case DEVIATING -> {
                        deviations.merge(u.state().direction(), 1, Integer::sum);
                        out.append(t).append("deviating ").append(u.state().direction()).append('\n');
                    }
                    case SUSTAINED_TILT -> out.append(t).append("sustained ").append(u.state().direction()).append('\n');
                    default -> out.append(t).append(k.caseName()).append('\n');
                }
            }
            if (u.reminder() != null) {
                ReminderDecision r = u.reminder();
                out.append(t).append("REMINDER ").append(r.direction()).append(" (").append(f(r.deviationDegrees(), 1))
                        .append(" deg, sustained ").append(f(r.sustainedSeconds(), 1)).append(" s)\n");
            }
            previous = k;
        }
        out.append("  summary: calibration ").append(result.calibrationOutcomes()).append(", axis calibration ")
                .append(result.axisCalibrationOutcomes()).append(", deviations ").append(deviations)
                .append(", episodes ").append(result.episodes().size()).append(", reminders ")
                .append(result.reminders().size()).append(", final state ").append(result.finalState()).append('\n');
        return out.toString();
    }

    /** Resolves a path against the working directory, then the repository root. */
    static Path resolve(String name) {
        Path p = Path.of(name);
        if (p.isAbsolute() || p.toFile().exists()) {
            return p;
        }
        try {
            Path fromRoot = Fixtures.repoRoot().resolve(name);
            if (fromRoot.toFile().exists()) {
                return fromRoot;
            }
        } catch (IllegalStateException ignored) {
            // no repository root above the working directory
        }
        return p;
    }

    /** Runs the CLI, printing to {@code out}; returns the exit status. */
    public static int run(String[] args, PrintStream out) {
        ObjectNode overrides = Json.object();
        List<String> files = new ArrayList<>();
        for (int i = 0; i < args.length; i++) {
            switch (args[i]) {
                case "--set" -> parseOverride(args[++i], overrides);
                case "-h", "--help" -> {
                    out.println("usage: Replay [--set key=value]... <recording-or-fixture.json>...");
                    return 0;
                }
                default -> files.add(args[i]);
            }
        }
        if (files.isEmpty()) {
            out.println("usage: Replay [--set key=value]... <recording-or-fixture.json>...");
            return 2;
        }
        for (String name : files) {
            Path path = resolve(name);
            out.print(summarize(path.getFileName().toString(), Fixtures.loadFixture(path), overrides));
            out.println();
        }
        return 0;
    }

    public static void main(String[] args) {
        int status = run(args, System.out);
        if (status != 0) {
            System.exit(status);
        }
    }
}
