package com.bachnguyennn.align.reference;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/** The {@code exec:java@replay} and {@code exec:java@rereference} tools, with committed fixtures as input. */
class ReplayToolsTest {

    private static Path fixture(String name) {
        return Fixtures.fixtureDir().resolve(name + ".json");
    }

    private static String runReplay(String... args) {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        int status = Replay.run(args, new PrintStream(bytes, true, StandardCharsets.UTF_8));
        assertEquals(0, status);
        return bytes.toString(StandardCharsets.UTF_8);
    }

    @Test
    void replaySummaryOfAFixture() {
        String text = runReplay(fixture("nod_axis_calibration_yawed_earbud").toString());
        assertTrue(text.contains("== nod_axis_calibration_yawed_earbud.json (fixture"), text);
        assertTrue(text.contains("neutral calibration succeeded"), text);
        assertTrue(text.contains("axis calibration succeeded (yaw +2"), text);
        assertTrue(text.contains("learned axes: forward"), text);
        assertTrue(text.contains("REMINDER forward"), text);
        assertTrue(text.contains("episode forward"), text);
        assertTrue(text.contains("largest gap"), text);
        assertTrue(text.contains("p5 / p50 / p95"), text);
        assertTrue(text.contains("reminders 1, final state neutral"), text);
    }

    @Test
    void replayOverridesConfigurationValues() {
        String path = fixture("gradual_forward_slouch").toString();
        assertTrue(runReplay(path).contains("reminders 1,"));
        String raised = runReplay("--set", "forwardThresholdDegrees=30", path);
        assertTrue(raised.contains("overrides: {\"forwardThresholdDegrees\":30}"), raised);
        assertTrue(raised.contains("reminders 0,"), raised);
        assertThrows(IllegalArgumentException.class, () -> runReplay("--set", "noSuchKey=1", path));
        assertThrows(IllegalArgumentException.class, () -> runReplay("--set", "forwardThresholdDegrees", path));
    }

    @Test
    void replayShowsGapsAndSeveralFiles() {
        String text = runReplay(fixture("disconnect_mid_tilt").toString(), fixture("steady_neutral").toString());
        assertTrue(text.contains("(> maxSampleGap: acts as an interrupt)"), text);
        assertTrue(text.contains("s gap (interrupt at t 51.96)"), text);
        assertTrue(text.contains("== steady_neutral.json"), text);
    }

    /** A recording (fixture schema with a recording block, no expected/reference/truth) replays too. */
    @Test
    void replayAcceptsARecording(@TempDir Path dir) throws IOException {
        ObjectNode fx = Fixtures.loadFixture(fixture("calibration_brief_fidget"));
        ObjectNode rec = Json.object();
        rec.put("schemaVersion", 1);
        rec.put("name", "test-recording");
        ObjectNode meta = rec.putObject("recording");
        meta.put("appVersion", "0.0-test");
        meta.put("device", "test");
        meta.put("headphones", "test");
        meta.put("notes", "built from a fixture by ReplayToolsTest");
        meta.put("createdAt", "2026-10-31T00:00:00Z");
        rec.set("sampleRateHz", fx.get("sampleRateHz"));
        rec.set("startTimestamp", fx.get("startTimestamp"));
        rec.set("actions", fx.get("actions"));
        rec.set("samples", fx.get("samples"));
        Path path = dir.resolve("rec.json");
        Files.writeString(path, Json.dumps(rec, 2), StandardCharsets.UTF_8);
        String text = runReplay(path.toString());
        assertTrue(text.contains("(recording, name test-recording)"), text);
        assertTrue(text.contains("headphones: test"), text);
        assertTrue(text.contains("neutral calibration succeeded"), text);
    }

    @Test
    void percentileIsNearestRank() {
        double[] v = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
        assertEquals(1.0, Replay.percentile(v, 5));
        assertEquals(5.0, Replay.percentile(v, 50));
        assertEquals(10.0, Replay.percentile(v, 95));
        assertTrue(Double.isNaN(Replay.percentile(new double[0], 50)));
    }

    // MARK: - Rereference

    @Test
    void committedReferenceBlocksAreCurrent() {
        assertEquals(List.of(), Rereference.run(Fixtures.fixtureDir(), true));
    }

    @Test
    void rereferenceRewritesOnlyChangedReferenceBlocks(@TempDir Path dir) throws IOException {
        Path stale = dir.resolve("lateral_right_tilt.json");
        Path current = dir.resolve("steady_neutral.json");
        Files.copy(fixture("lateral_right_tilt"), stale);
        Files.copy(fixture("steady_neutral"), current);
        String original = Files.readString(stale, StandardCharsets.UTF_8);
        byte[] currentBytes = Files.readAllBytes(current);
        ObjectNode fx = (ObjectNode) Json.parse(original);
        ((ObjectNode) fx.get("reference")).put("stateTransitions", 99);
        Files.writeString(stale, Generator.dumpsFixture(fx), StandardCharsets.UTF_8);

        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        assertEquals(1, Rereference.run(new String[] {"--check", "--dir", dir.toString()},
                new PrintStream(bytes, true, StandardCharsets.UTF_8)));
        assertTrue(bytes.toString(StandardCharsets.UTF_8).contains("lateral_right_tilt.json [stateTransitions]"));

        assertEquals(0, Rereference.run(new String[] {"--dir", dir.toString()}, new PrintStream(new ByteArrayOutputStream())));
        JsonNode rewritten = Fixtures.loadFixture(stale);
        JsonNode before = Json.parse(original);
        assertEquals(before.get("reference").get("stateTransitions"), rewritten.get("reference").get("stateTransitions"));
        assertEquals("align-tools " + AlignReference.VERSION, rewritten.get("reference").get("producedBy").asText());
        for (String key : List.of("samples", "expected", "truth", "generator", "config", "actions")) {
            assertEquals(before.get(key), rewritten.get(key), key);
        }
        // Everything outside the reference block is byte-identical.
        String text = Files.readString(stale, StandardCharsets.UTF_8);
        assertEquals(original.substring(0, original.indexOf("\"reference\"")), text.substring(0, text.indexOf("\"reference\"")));
        assertEquals(original.substring(original.indexOf("\"samples\"")), text.substring(text.indexOf("\"samples\"")));
        assertTrue(java.util.Arrays.equals(currentBytes, Files.readAllBytes(current)));
    }
}
