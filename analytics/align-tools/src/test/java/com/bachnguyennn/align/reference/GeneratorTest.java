package com.bachnguyennn.align.reference;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.stream.Stream;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;

/**
 * The Java generator (replaces test_generator_is_deterministic, which compared against numpy's
 * streams). Generates every scenario into a temporary directory, never into shared/fixtures.
 */
class GeneratorTest {

    @TempDir
    static Path firstRun;
    @TempDir
    static Path secondRun;

    private static List<Path> written;

    @BeforeAll
    static void generateTwice() {
        written = Generator.writeAll(firstRun);
        Generator.writeAll(secondRun);
    }

    static Stream<String> scenarios() {
        return Generator.SCENARIOS.keySet().stream();
    }

    @Test
    void writesEveryScenario() {
        assertEquals(Generator.SCENARIOS.keySet().stream().map(n -> n + ".json").toList(),
                written.stream().map(p -> p.getFileName().toString()).toList());
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("scenarios")
    void sameSeedIsByteIdentical(String name) throws IOException {
        assertArrayEquals(Files.readAllBytes(firstRun.resolve(name + ".json")),
                Files.readAllBytes(secondRun.resolve(name + ".json")));
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("scenarios")
    void generatedFixturePassesItsExpectedBlock(String name) {
        ObjectNode fx = Fixtures.loadFixture(firstRun.resolve(name + ".json"));
        assertEquals(List.of(), Fixtures.checkExpected(fx, Fixtures.replay(fx)));
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("scenarios")
    void generatedFixtureHasCurrentReferenceAndValidSchema(String name) {
        ObjectNode fx = Fixtures.loadFixture(firstRun.resolve(name + ".json"));
        assertEquals(fx.get("reference"), Fixtures.referenceBlock(Fixtures.replay(fx)));
        assertEquals(Fixtures.SCHEMA_VERSION, fx.get("schemaVersion").asInt());
        assertEquals(name, fx.get("name").asText());
        JsonNode samples = fx.get("samples");
        for (int i = 1; i < samples.size(); i++) {
            assertTrue(samples.get(i).get("t").asDouble() > samples.get(i - 1).get("t").asDouble());
        }
        JsonNode generator = fx.get("generator");
        assertEquals(Generator.GENERATOR_SCRIPT, generator.get("script").asText());
        assertEquals("java " + System.getProperty("java.version"), generator.get("runtime").asText());
        assertTrue(!generator.has("numpy"));
    }

    /**
     * {@code expected} comes from the noise-free truth, which the port reproduces exactly; only
     * brief_glances_down draws its glances at random, so its truth differs.
     */
    @ParameterizedTest(name = "{0}")
    @MethodSource("scenarios")
    void expectedBlockMatchesCommittedPythonFixture(String name) {
        ObjectNode committed = Fixtures.loadFixture(Fixtures.fixtureDir().resolve(name + ".json"));
        ObjectNode generated = Fixtures.loadFixture(firstRun.resolve(name + ".json"));
        if (name.equals("brief_glances_down")) {
            assertNotEquals(committed.get("truth").get("glances"), generated.get("truth").get("glances"));
            assertEquals(committed.get("expected"), generated.get("expected"));  // no episodes either way
            return;
        }
        assertEquals(committed.get("expected"), generated.get("expected"));
        for (String key : List.of("description", "sampleRateHz", "startTimestamp", "config", "actions")) {
            assertEquals(committed.get(key), generated.get(key), key);
        }
    }

    /** The D-017 fixtures were written by this generator, so it reproduces them exactly. */
    @ParameterizedTest(name = "{0}")
    @MethodSource("scenarios")
    void javaGeneratedFixturesAreReproducedExactly(String name) {
        ObjectNode committed = Fixtures.loadFixture(Fixtures.fixtureDir().resolve(name + ".json"));
        if (!committed.get("generator").path("runtime").asText().startsWith("java")) {
            assertTrue(Generator.PYTHON_SCENARIOS.contains(name), name);
            return;
        }
        assertTrue(!Generator.PYTHON_SCENARIOS.contains(name), name);
        ObjectNode generated = Fixtures.loadFixture(firstRun.resolve(name + ".json"));
        for (String key : List.of("samples", "truth", "expected", "reference", "actions", "config", "description")) {
            assertEquals(committed.get(key), generated.get(key), key);
        }
    }

    /** A zero mount yaw leaves the pose model bit for bit unchanged (existing scenarios are unaffected). */
    @Test
    void zeroMountYawIsTheOldPoseModel() {
        assertEquals(Pose.poseAttitude(12, -5, 33, 8, -3), Pose.poseAttitude(12, -5, 33, 8, -3, 0.0, null));
        assertTrue(!Pose.poseAttitude(12, -5, 33, 8, -3).equals(Pose.poseAttitude(12, -5, 33, 8, -3, 10.0, null)));
        ObjectNode truth = (ObjectNode) Generator.synthesize(Generator.steadyNeutral()).fixture().get("truth");
        assertTrue(!truth.get("mountDegrees").has("yaw"));
        ObjectNode yawed = (ObjectNode) Generator.synthesize(Generator.nodAxisCalibrationYawedEarbud()).fixture().get("truth");
        assertEquals(25.0, yawed.get("mountDegrees").get("yaw").asDouble());
    }

    /** Positive mount yaw is learned as positive yaw (the sign documented in the fixtures README). */
    @Test
    void trueYawMatchesMountYawWithoutPitchAndRoll() {
        Approx.assertApprox(25.0, Pose.trueYawDegrees(0, 0, 25, null), 1e-9);
        Approx.assertApprox(-15.0, Pose.trueYawDegrees(0, 0, -15, null), 1e-9);
        Approx.assertApprox(25.42, Pose.trueYawDegrees(8, -3, 25, null), 0.01);
    }

    @Test
    void mainWithOnlyWritesTheNamedScenarios(@TempDir Path out) throws IOException {
        Generator.main(new String[] {"--out", out.toString(), "--only", "nod_axis_calibration_no_nod"});
        try (Stream<Path> files = Files.list(out)) {
            assertEquals(List.of("nod_axis_calibration_no_nod.json"),
                    files.map(p -> p.getFileName().toString()).toList());
        }
    }

    @Test
    void differentSeedsGiveDifferentSamples() {
        JsonNode a = Generator.synthesize(Generator.steadyNeutral(1)).fixture().get("samples");
        JsonNode b = Generator.synthesize(Generator.steadyNeutral(2)).fixture().get("samples");
        assertEquals(a.size(), b.size());
        assertNotEquals(a, b);
    }

    @Test
    void truthArraysCoverKeptSamples() {
        Generator.Synthesis s = Generator.synthesize(Generator.disconnectMidTilt());
        int n = s.fixture().get("samples").size();
        assertEquals(n, s.truth().t().length);
        // 72 s at 25 Hz = 1801 samples, minus the 5 s gap (125 samples).
        assertEquals(1801 - 125, n);
        for (double t : s.truth().t()) {
            assertTrue(t < 52.0 - 1e-9 || t >= 57.0 - 1e-9);
        }
    }

    @Test
    void mainWritesToOutDirectory(@TempDir Path out) throws IOException {
        Generator.main(new String[] {"--out", out.toString()});
        for (Map.Entry<String, ?> e : Generator.SCENARIOS.entrySet()) {
            assertTrue(Files.isRegularFile(out.resolve(e.getKey() + ".json")));
        }
    }
}
