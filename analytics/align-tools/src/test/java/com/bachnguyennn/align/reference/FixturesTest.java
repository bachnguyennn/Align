package com.bachnguyennn.align.reference;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.bachnguyennn.align.reference.Fixtures.ReplayResult;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.TreeSet;
import java.util.stream.Collectors;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;

/**
 * Port of tests/test_fixtures.py, plus the Java/Python parity check: each committed fixture's
 * {@code reference} block (written by the Python reference) must be reproduced by the Java
 * pipeline. Fixtures are found by walking up from the working directory; none found is a failure.
 */
class FixturesTest {

    /** Tolerance for timestamps (they are sample timestamps, so in practice exactly equal). */
    private static final double TIME_TOLERANCE = 1e-9;
    /** Tolerance for degree values the reference block rounds to 4 decimals. */
    private static final double DEGREE_TOLERANCE = 1e-4;

    static List<Path> fixtures() {
        List<Path> paths = Fixtures.fixturePaths();
        if (paths.isEmpty()) {
            throw new IllegalStateException("no fixtures in " + Fixtures.fixtureDir());
        }
        return paths;
    }

    @Test
    void allRequiredFixturesExist() {
        Set<String> names = fixtures().stream().map(Fixtures::stem).collect(Collectors.toCollection(TreeSet::new));
        assertEquals(new TreeSet<>(Generator.SCENARIOS.keySet()), names);
    }

    @Test
    void fixtureTotalSizeIsSmall() throws IOException {
        long total = 0;
        for (Path p : fixtures()) {
            total += Files.size(p);
        }
        assertTrue(total < 1.25 * 1024 * 1024, "total fixture size " + total);
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("fixtures")
    void fixtureSchema(Path path) {
        ObjectNode fx = Fixtures.loadFixture(path);
        assertEquals(Fixtures.SCHEMA_VERSION, fx.get("schemaVersion").asInt());
        assertEquals(Fixtures.stem(path), fx.get("name").asText());
        assertTrue(fx.get("sampleRateHz").asDouble() > 0);
        JsonNode samples = fx.get("samples");
        for (int i = 1; i < samples.size(); i++) {
            assertTrue(samples.get(i).get("t").asDouble() > samples.get(i - 1).get("t").asDouble(),
                    "timestamps must strictly increase at sample " + i);
        }
        for (int i = 0; i < Math.min(50, samples.size()); i++) {
            assertEquals(4, samples.get(i).get("q").size());
            assertEquals(3, samples.get(i).get("g").size());
        }
        for (String key : List.of("calibrationOutcomes", "reminders", "episodes", "finalState", "tolerances")) {
            assertTrue(fx.get("expected").has(key), "expected." + key);
        }
    }

    /** Fixtures state their axes explicitly; they must equal the AlignCore default (D-011). */
    @ParameterizedTest(name = "{0}")
    @MethodSource("fixtures")
    void fixtureAxesMatchDefaultConvention(Path path) {
        HeadAxisConvention axes = HeadAxisConvention.DEFAULT;
        JsonNode config = Fixtures.loadFixture(path).get("config");
        PostureConfiguration parsed = PostureConfiguration.fromOverrides(config);
        assertTrue(config.has("forwardAxis") && config.has("lateralAxis"));
        assertEquals(axes.forwardAxis(), parsed.axes().forwardAxis());
        assertEquals(axes.lateralAxis(), parsed.axes().lateralAxis());
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("fixtures")
    void fixtureExpectedOutcomes(Path path) {
        ObjectNode fx = Fixtures.loadFixture(path);
        assertEquals(List.of(), Fixtures.checkExpected(fx, Fixtures.replay(fx)));
    }

    /** The stored {@code reference} (written by Python, used by Swift) is reproduced by Java. */
    @ParameterizedTest(name = "{0}")
    @MethodSource("fixtures")
    void fixtureReferenceMatchesPython(Path path) {
        ObjectNode fx = Fixtures.loadFixture(path);
        JsonNode want = fx.get("reference");
        JsonNode got = Fixtures.referenceBlock(Fixtures.replay(fx));
        List<String> errors = new ArrayList<>();
        double[] maxDiff = {0.0, 0.0};  // timestamps, 4-decimal rounded values

        if (!got.get("calibrationOutcomes").equals(want.get("calibrationOutcomes"))) {
            errors.add("calibrationOutcomes " + got.get("calibrationOutcomes") + " != " + want.get("calibrationOutcomes"));
        }
        compareList("reminders", got.get("reminders"), want.get("reminders"), errors, (g, w, prefix) -> {
            same(prefix + "direction", g.get("direction"), w.get("direction"), errors);
            near(prefix + "t", g, w, "t", TIME_TOLERANCE, maxDiff, 0, errors);
            near(prefix + "deviationDegrees", g, w, "deviationDegrees", DEGREE_TOLERANCE, maxDiff, 1, errors);
            near(prefix + "sustainedSeconds", g, w, "sustainedSeconds", DEGREE_TOLERANCE, maxDiff, 1, errors);
        });
        compareList("episodes", got.get("episodes"), want.get("episodes"), errors, (g, w, prefix) -> {
            same(prefix + "direction", g.get("direction"), w.get("direction"), errors);
            near(prefix + "start", g, w, "start", TIME_TOLERANCE, maxDiff, 0, errors);
            near(prefix + "end", g, w, "end", TIME_TOLERANCE, maxDiff, 0, errors);
            near(prefix + "peakDeviationDegrees", g, w, "peakDeviationDegrees", DEGREE_TOLERANCE, maxDiff, 1, errors);
            same(prefix + "reminderTriggered", g.get("reminderTriggered"), w.get("reminderTriggered"), errors);
        });
        same("finalState", got.get("finalState"), want.get("finalState"), errors);
        same("stateTransitions", got.get("stateTransitions"), want.get("stateTransitions"), errors);

        boolean exact = sameIgnoringProducer(got, want);
        System.out.printf(Locale.ROOT, "parity %-30s reminders=%d episodes=%d transitions=%s max|dt|=%.3g "
                        + "max|d rounded|=%.3g exact=%s%n", Fixtures.stem(path), got.get("reminders").size(),
                got.get("episodes").size(), got.get("stateTransitions"), maxDiff[0], maxDiff[1], exact);
        assertEquals(List.of(), errors);
    }

    /** True when the Java block equals the Python one bit for bit, apart from {@code producedBy}. */
    private static boolean sameIgnoringProducer(JsonNode got, JsonNode want) {
        ObjectNode a = ((ObjectNode) got).deepCopy();
        ObjectNode b = ((ObjectNode) want).deepCopy();
        a.remove("producedBy");
        b.remove("producedBy");
        return a.equals(b);
    }

    private interface ItemCheck {
        void check(JsonNode got, JsonNode want, String prefix);
    }

    private static void compareList(String name, JsonNode got, JsonNode want, List<String> errors, ItemCheck check) {
        if (got.size() != want.size()) {
            errors.add(name + " count " + got.size() + " != " + want.size() + ": " + got);
            return;
        }
        for (int i = 0; i < got.size(); i++) {
            check.check(got.get(i), want.get(i), name + "[" + i + "].");
        }
    }

    private static void same(String what, JsonNode got, JsonNode want, List<String> errors) {
        if (!got.equals(want)) {
            errors.add(what + " " + got + " != " + want);
        }
    }

    private static void near(String what, JsonNode got, JsonNode want, String key, double tolerance,
                             double[] maxDiff, int slot, List<String> errors) {
        double diff = Math.abs(got.get(key).asDouble() - want.get(key).asDouble());
        maxDiff[slot] = Math.max(maxDiff[slot], diff);
        if (!(diff <= tolerance)) {
            errors.add(what + " " + got.get(key) + " != " + want.get(key) + " (tolerance " + tolerance + ")");
        }
    }

    /** The Java writer reproduces the Python fixture layout byte for byte. */
    @ParameterizedTest(name = "{0}")
    @MethodSource("fixtures")
    void fixtureFileLayoutRoundTrips(Path path) throws IOException {
        String text = Files.readString(path, StandardCharsets.UTF_8);
        ObjectNode fx = (ObjectNode) Json.parse(text);
        assertEquals(text, Generator.dumpsFixture(fx));
    }

    @Test
    void replayRejectsUnknownActions() {
        ObjectNode fx = Fixtures.loadFixture(fixtures().get(0));
        fx.withArray("actions").addObject().put("t", 1.0).put("type", "dance");
        IllegalArgumentException e = assertThrows(IllegalArgumentException.class, () -> Fixtures.replay(fx));
        assertTrue(e.getMessage().contains("dance"));
    }
}
