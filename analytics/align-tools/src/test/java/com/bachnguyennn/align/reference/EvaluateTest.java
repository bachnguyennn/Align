package com.bachnguyennn.align.reference;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import org.junit.jupiter.api.Test;

/** Port of tests/test_evaluate.py, plus parity of the noise-free table with the Python report. */
class EvaluateTest {

    private static final String PYTHON_REPORT = "analytics/experiments/results/evaluation.md";
    private static final String AXIS_SECTION = "## Axis projection with earbud mounting offset (noise-free, 20° poses)";

    @Test
    void axisProjectionTableRenders() {
        String text = Evaluate.axisProjection();
        assertTrue(text.startsWith("| mount pitch/roll"));
        assertTrue(text.contains("10/0"));
    }

    @Test
    void shortGlanceNeverRemindsAndLongHoldDoes() {
        assertEquals(List.of(), Fixtures.replay(Evaluate.build(Evaluate.glanceSpec(1, 10.0))).reminders());
        assertEquals(1, Fixtures.replay(Evaluate.build(Evaluate.holdSpec(1, 25.0, 0.0, 45.0))).reminders().size());
    }

    /** The axis projection uses no random data, so it must equal the Python report's table exactly. */
    @Test
    void axisProjectionTableMatchesPythonReport() throws IOException {
        Path report = Fixtures.repoRoot().resolve(PYTHON_REPORT);
        String text = Files.readString(report).replace("\r\n", "\n");
        int start = text.indexOf(AXIS_SECTION);
        assertTrue(start >= 0, "section missing from " + report);
        int tableStart = text.indexOf("| ", start);
        int tableEnd = text.indexOf("\n\n", tableStart);
        assertEquals(text.substring(tableStart, tableEnd), Evaluate.axisProjection());
    }

    @Test
    void formattingMatchesPython() {
        assertEquals("n/a", Evaluate.fmt(null));
        assertEquals("n/a", Evaluate.fmt(Double.NaN));
        assertEquals("n/a", Evaluate.stats(List.of()));
        assertEquals("1.50 (min 1.00, max 2.00)", Evaluate.stats(List.of(1.0, 2.0)));
        assertEquals("| a | b |\n|---|---|\n| 1 | 2 |", Evaluate.table(List.of("a", "b"), List.of(List.of("1", "2"))));
    }
}
