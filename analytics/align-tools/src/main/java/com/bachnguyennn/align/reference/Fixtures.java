package com.bachnguyennn.align.reference;

import com.bachnguyennn.align.reference.Geometry.Quat;
import com.bachnguyennn.align.reference.Geometry.Vec3;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.stream.Stream;

/**
 * Loading, replaying and checking motion fixtures (format: shared/fixtures/README.md).
 *
 * <p>The replay loop here is mirrored by the Swift {@code FixtureReplayTests}. A fixture is kept
 * as its JSON tree ({@link ObjectNode}), like the Python dict.
 */
public final class Fixtures {

    public static final int SCHEMA_VERSION = 1;
    /** Fixture directory relative to the repository root. */
    public static final String FIXTURE_SUBDIR = "shared/fixtures/motion";

    private Fixtures() {}

    /**
     * The repository root: the first directory, walking up from the working directory, that
     * contains {@code shared/fixtures/motion}.
     */
    public static Path repoRoot() {
        Path dir = Path.of("").toAbsolutePath();
        for (Path p = dir; p != null; p = p.getParent()) {
            if (Files.isDirectory(p.resolve(FIXTURE_SUBDIR))) {
                return p;
            }
        }
        throw new IllegalStateException("no " + FIXTURE_SUBDIR + " found above " + dir);
    }

    public static Path fixtureDir() {
        return repoRoot().resolve(FIXTURE_SUBDIR);
    }

    public static ObjectNode loadFixture(Path path) {
        return Json.load(path);
    }

    /** The committed fixtures, sorted by file name. */
    public static List<Path> fixturePaths() {
        return fixturePaths(fixtureDir());
    }

    public static List<Path> fixturePaths(Path directory) {
        try (Stream<Path> files = Files.list(directory)) {
            return files.filter(p -> p.getFileName().toString().endsWith(".json"))
                    .sorted(Comparator.comparing(p -> p.getFileName().toString()))
                    .toList();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /** File name without {@code .json}, Python {@code Path.stem}. */
    public static String stem(Path path) {
        String name = path.getFileName().toString();
        return name.endsWith(".json") ? name.substring(0, name.length() - 5) : name;
    }

    public static List<MotionSample> fixtureSamples(JsonNode fx) {
        List<MotionSample> samples = new ArrayList<>(fx.get("samples").size());
        for (JsonNode s : fx.get("samples")) {
            JsonNode q = s.get("q");
            JsonNode g = s.get("g");
            JsonNode r = s.get("r");
            samples.add(new MotionSample(
                    s.get("t").asDouble(),
                    new Quat(q.get(0).asDouble(), q.get(1).asDouble(), q.get(2).asDouble(), q.get(3).asDouble()),
                    isPresent(g) ? vec3(g) : null,
                    isPresent(r) ? vec3(r) : null));
        }
        return samples;
    }

    /** The fixture's stored baseline (optionally with {@code learnedAxes}), or null. */
    public static NeutralBaseline fixtureBaseline(JsonNode fx) {
        JsonNode b = fx.get("baseline");
        if (!isPresent(b) || b.isEmpty()) {
            return null;
        }
        JsonNode learned = b.get("learnedAxes");
        HeadAxisConvention learnedAxes = isPresent(learned)
                ? new HeadAxisConvention(vec3(learned.get("forwardAxis")), vec3(learned.get("lateralAxis")))
                : null;
        return new NeutralBaseline(
                vec3(b.get("gravity")),
                0.0,
                b.path("sampleCount").asInt(0),
                b.path("version").asInt(1),
                learnedAxes);
    }

    private static boolean isPresent(JsonNode node) {
        return node != null && !node.isNull();
    }

    private static Vec3 vec3(JsonNode a) {
        return new Vec3(a.get(0).asDouble(), a.get(1).asDouble(), a.get(2).asDouble());
    }

    /**
     * Replay outcome. {@code updates} is filled only when requested; {@code tilts} (every non-null
     * update tilt, in order) always. {@code finalBaseline} is the monitor's baseline at the end
     * (its {@code learnedAxes} are the learned axes, if any) and {@code configuration} the one used.
     */
    public record ReplayResult(
            List<ReminderDecision> reminders,
            List<PostureEpisode> episodes,
            List<String> calibrationOutcomes,
            List<String> axisCalibrationOutcomes,
            String finalState,
            int stateTransitions,
            List<PostureUpdate> updates,
            List<TiltEstimate> tilts,
            NeutralBaseline finalBaseline,
            PostureConfiguration configuration) {

        /** Learned axes at the end of the replay, or null. */
        public HeadAxisConvention learnedAxes() {
            return finalBaseline != null ? finalBaseline.learnedAxes() : null;
        }

        /** Signed yaw (degrees) of the learned forward axis from {@code configuration.axes}, or null. */
        public Double learnedYawDegrees() {
            HeadAxisConvention learned = learnedAxes();
            if (learned == null) {
                return null;
            }
            return AxisCalibrationService.signedYawDegrees(learned.forwardAxis(), finalBaseline.gravity(),
                    configuration.axes());
        }

        /** Largest |lateralDegrees| of the tilts with from ≤ t ≤ to (0 if none). */
        public double maxAbsLateralDegrees(double from, double to) {
            double max = 0.0;
            for (TiltEstimate tilt : tilts) {
                if (tilt.timestamp() >= from && tilt.timestamp() <= to) {
                    max = Math.max(max, Math.abs(tilt.lateralDegrees()));
                }
            }
            return max;
        }
    }

    public static ReplayResult replay(JsonNode fx) {
        return replay(fx, null, false, true, null);
    }

    public static ReplayResult replay(JsonNode fx, PostureConfiguration configuration) {
        return replay(fx, configuration, false, true, null);
    }

    public static ReplayResult replay(JsonNode fx, PostureConfiguration configuration, boolean keepUpdates) {
        return replay(fx, configuration, keepUpdates, true, null);
    }

    public static ReplayResult replay(JsonNode fx, PostureConfiguration configuration, boolean keepUpdates,
                                      boolean orthogonalizeAxes, List<MotionSample> samples) {
        return replay(fx, configuration, keepUpdates, orthogonalizeAxes, samples,
                AxisCalibrationService.LineFit.PRINCIPAL_AXIS);
    }

    /**
     * Replays a fixture (or recording). Each action is applied before the first sample whose
     * t ≥ action t; actions after the last sample are applied at the end. {@code configuration}
     * null means the fixture's {@code config}; {@code samples} null means the fixture's samples.
     * {@code lineFit} other than the default is for the evaluation only.
     */
    public static ReplayResult replay(JsonNode fx, PostureConfiguration configuration, boolean keepUpdates,
                                      boolean orthogonalizeAxes, List<MotionSample> samples,
                                      AxisCalibrationService.LineFit lineFit) {
        PostureConfiguration config = configuration != null
                ? configuration
                : PostureConfiguration.fromOverrides(fx.get("config"));
        PostureMonitor monitor = new PostureMonitor(config, fixtureBaseline(fx), orthogonalizeAxes, lineFit);
        if (samples == null) {
            samples = fixtureSamples(fx);
        }
        List<JsonNode> actions = new ArrayList<>();
        fx.path("actions").forEach(actions::add);
        actions.sort(Comparator.comparingDouble(a -> a.get("t").asDouble()));
        Recorder recorder = new Recorder(keepUpdates);

        int ai = 0;
        for (MotionSample sample : samples) {
            while (ai < actions.size() && actions.get(ai).get("t").asDouble() <= sample.timestamp()) {
                apply(monitor, actions.get(ai), recorder);
                ai++;
            }
            recorder.record(monitor.process(sample));
        }
        while (ai < actions.size()) {
            apply(monitor, actions.get(ai), recorder);
            ai++;
        }
        return new ReplayResult(List.copyOf(recorder.reminders), List.copyOf(recorder.episodes),
                List.copyOf(recorder.calibrationOutcomes), List.copyOf(recorder.axisCalibrationOutcomes),
                monitor.state().kind().caseName(), recorder.stateTransitions, List.copyOf(recorder.updates),
                List.copyOf(recorder.tilts), monitor.baseline(), config);
    }

    /** Fixture action types, in the order documented in shared/fixtures/README.md. */
    public static final List<String> ACTION_TYPES = List.of("beginCalibration", "cancelCalibration",
            "beginAxisCalibration", "cancelAxisCalibration", "clearLearnedAxes", "resetCooldown", "interrupt");

    private static void apply(PostureMonitor monitor, JsonNode action, Recorder recorder) {
        String kind = action.get("type").asText();
        switch (kind) {
            case "beginCalibration" -> monitor.beginCalibration();
            case "cancelCalibration" -> monitor.cancelCalibration();
            case "beginAxisCalibration" -> monitor.beginAxisCalibration();
            case "cancelAxisCalibration" -> monitor.cancelAxisCalibration();
            case "clearLearnedAxes" -> monitor.clearLearnedAxes();
            case "resetCooldown" -> monitor.resetCooldown();
            case "interrupt" -> recorder.record(monitor.interrupt(action.get("t").asDouble()));
            default -> throw new IllegalArgumentException("unknown action type: " + kind);
        }
    }

    private static final class Recorder {
        final boolean keepUpdates;
        final List<ReminderDecision> reminders = new ArrayList<>();
        final List<PostureEpisode> episodes = new ArrayList<>();
        final List<String> calibrationOutcomes = new ArrayList<>();
        final List<String> axisCalibrationOutcomes = new ArrayList<>();
        final List<PostureUpdate> updates = new ArrayList<>();
        final List<TiltEstimate> tilts = new ArrayList<>();
        int stateTransitions = 0;
        PostureState.Kind previousKind = null;

        Recorder(boolean keepUpdates) {
            this.keepUpdates = keepUpdates;
        }

        void record(PostureUpdate update) {
            if (keepUpdates) {
                updates.add(update);
            }
            if (update.tilt() != null) {
                tilts.add(update.tilt());
            }
            if (update.axisCalibrationOutcome() != null) {
                axisCalibrationOutcomes.add(update.axisCalibrationOutcome().name());
            }
            if (update.reminder() != null) {
                reminders.add(update.reminder());
            }
            if (update.completedEpisode() != null) {
                episodes.add(update.completedEpisode());
            }
            if (update.calibrationOutcome() != null) {
                calibrationOutcomes.add(update.calibrationOutcome().name());
            }
            PostureState.Kind kind = update.state().kind();
            if (previousKind != null && kind != previousKind) {
                stateTransitions++;
            }
            previousKind = kind;
        }
    }

    /** Mismatches between a replay and the fixture's {@code expected} block (empty = pass). */
    public static List<String> checkExpected(JsonNode fx, ReplayResult result) {
        JsonNode exp = fx.get("expected");
        double tol = exp.path("tolerances").path("timeSeconds").asDouble(2.0);
        List<String> errors = new ArrayList<>();
        if (exp.has("calibrationOutcomes")) {
            List<String> want = strings(exp.get("calibrationOutcomes"));
            if (!result.calibrationOutcomes().equals(want)) {
                errors.add("calibrationOutcomes " + result.calibrationOutcomes() + " != " + want);
            }
        }
        JsonNode wantReminders = exp.get("reminders");
        if (result.reminders().size() != wantReminders.size()) {
            List<String> got = result.reminders().stream()
                    .map(r -> "(" + PythonFormat.repr(PythonFormat.round(r.timestamp(), 2)) + ", " + r.direction() + ")")
                    .toList();
            errors.add("reminder count " + result.reminders().size() + " != " + wantReminders.size() + ": " + got);
        } else {
            for (int i = 0; i < wantReminders.size(); i++) {
                ReminderDecision got = result.reminders().get(i);
                JsonNode want = wantReminders.get(i);
                if (!got.direction().rawValue().equals(want.get("direction").asText())) {
                    errors.add("reminder direction " + got.direction() + " != " + want.get("direction").asText());
                }
                if (Math.abs(got.timestamp() - want.get("t").asDouble()) > tol) {
                    errors.add("reminder t " + PythonFormat.fixed(got.timestamp(), 3) + " not within " + tol
                            + " of " + want.get("t"));
                }
            }
        }
        JsonNode wantEpisodes = exp.get("episodes");
        if (result.episodes().size() != wantEpisodes.size()) {
            errors.add("episode count " + result.episodes().size() + " != " + wantEpisodes.size());
        } else {
            for (int i = 0; i < wantEpisodes.size(); i++) {
                PostureEpisode got = result.episodes().get(i);
                JsonNode want = wantEpisodes.get(i);
                if (!got.direction().rawValue().equals(want.get("direction").asText())) {
                    errors.add("episode direction " + got.direction() + " != " + want.get("direction").asText());
                }
                if (Math.abs(got.startTimestamp() - want.get("start").asDouble()) > tol) {
                    errors.add("episode start " + PythonFormat.fixed(got.startTimestamp(), 3) + " not within " + tol
                            + " of " + want.get("start"));
                }
                if (Math.abs(got.endTimestamp() - want.get("end").asDouble()) > tol) {
                    errors.add("episode end " + PythonFormat.fixed(got.endTimestamp(), 3) + " not within " + tol
                            + " of " + want.get("end"));
                }
                if (got.reminderTriggered() != want.get("reminderTriggered").asBoolean()) {
                    errors.add("episode reminderTriggered " + got.reminderTriggered() + " != "
                            + want.get("reminderTriggered"));
                }
            }
        }
        if (exp.has("finalState") && !result.finalState().equals(exp.get("finalState").asText())) {
            errors.add("finalState " + result.finalState() + " != " + exp.get("finalState").asText());
        }
        if (exp.has("axisCalibrationOutcomes")) {
            List<String> want = strings(exp.get("axisCalibrationOutcomes"));
            if (!result.axisCalibrationOutcomes().equals(want)) {
                errors.add("axisCalibrationOutcomes " + result.axisCalibrationOutcomes() + " != " + want);
            }
        }
        JsonNode learned = exp.get("learnedAxes");
        if (isPresent(learned)) {
            boolean wantPresent = learned.get("present").asBoolean();
            Double yaw = result.learnedYawDegrees();
            if (wantPresent != (yaw != null)) {
                errors.add("learnedAxes present " + (yaw != null) + " != " + wantPresent);
            } else if (yaw != null && learned.has("yawDegrees")) {
                double want = learned.get("yawDegrees").asDouble();
                double yawTol = learned.path("toleranceDegrees").asDouble(2.0);
                if (Math.abs(yaw - want) > yawTol) {
                    errors.add("learned yaw " + PythonFormat.fixed(yaw, 3) + " not within " + yawTol + " of " + want);
                }
            }
        }
        JsonNode lateral = exp.get("maxAbsLateral");
        if (isPresent(lateral)) {
            double got = result.maxAbsLateralDegrees(lateral.get("from").asDouble(), lateral.get("to").asDouble());
            if (got > lateral.get("degrees").asDouble()) {
                errors.add("max |lateral| " + PythonFormat.fixed(got, 3) + " > " + lateral.get("degrees")
                        + " in [" + lateral.get("from") + ", " + lateral.get("to") + "]");
            }
        }
        return errors;
    }

    private static List<String> strings(JsonNode array) {
        List<String> out = new ArrayList<>();
        array.forEach(n -> out.add(n.asText()));
        return out;
    }

    /**
     * Exact output of this reference implementation, stored in fixtures for Swift parity.
     * {@code axisCalibrationOutcomes} and {@code learnedAxes} (6 decimals, or null) are written
     * only when an axis calibration finished during the replay, so blocks of fixtures without
     * one keep their v1 layout.
     */
    public static ObjectNode referenceBlock(ReplayResult result) {
        ObjectNode block = Json.object();
        block.put("producedBy", "align-tools " + AlignReference.VERSION);
        ArrayNode outcomes = block.putArray("calibrationOutcomes");
        result.calibrationOutcomes().forEach(outcomes::add);
        if (!result.axisCalibrationOutcomes().isEmpty()) {
            ArrayNode axisOutcomes = block.putArray("axisCalibrationOutcomes");
            result.axisCalibrationOutcomes().forEach(axisOutcomes::add);
            HeadAxisConvention learned = result.learnedAxes();
            if (learned == null) {
                block.putNull("learnedAxes");
            } else {
                ObjectNode axes = block.putObject("learnedAxes");
                axes.set("forwardAxis", rounded(learned.forwardAxis(), 6));
                axes.set("lateralAxis", rounded(learned.lateralAxis(), 6));
            }
        }
        ArrayNode reminders = block.putArray("reminders");
        for (ReminderDecision r : result.reminders()) {
            ObjectNode o = reminders.addObject();
            o.put("t", r.timestamp());
            o.put("direction", r.direction().rawValue());
            o.put("deviationDegrees", PythonFormat.round(r.deviationDegrees(), 4));
            o.put("sustainedSeconds", PythonFormat.round(r.sustainedSeconds(), 4));
        }
        ArrayNode episodes = block.putArray("episodes");
        for (PostureEpisode e : result.episodes()) {
            ObjectNode o = episodes.addObject();
            o.put("direction", e.direction().rawValue());
            o.put("start", e.startTimestamp());
            o.put("end", e.endTimestamp());
            o.put("peakDeviationDegrees", PythonFormat.round(e.peakDeviationDegrees(), 4));
            o.put("reminderTriggered", e.reminderTriggered());
        }
        block.put("finalState", result.finalState());
        block.put("stateTransitions", result.stateTransitions());
        return block;
    }

    static ArrayNode rounded(Vec3 v, int digits) {
        return Json.array(PythonFormat.round(v.x(), digits), PythonFormat.round(v.y(), digits),
                PythonFormat.round(v.z(), digits));
    }
}
