package com.bachnguyennn.align.reference;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;
import org.junit.jupiter.api.Test;

/** Port of tests/test_evaluate.py, plus parity of the noise-free table with the Python report. */
class EvaluateTest {

    /** The axis-projection table of the original Python report, frozen when the Python was removed (D-015). */
    private static final String PYTHON_AXIS_TABLE = "/python-axis-projection.md";

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
        try (InputStream in = EvaluateTest.class.getResourceAsStream(PYTHON_AXIS_TABLE)) {
            assertNotNull(in, PYTHON_AXIS_TABLE + " missing");
            String expected = new String(in.readAllBytes(), StandardCharsets.UTF_8).replace("\r\n", "\n").strip();
            assertEquals(expected, Evaluate.axisProjection());
        }
    }

    @Test
    void d017TablesRenderAndShowTheExpectedEffects() {
        String crosstalk = Evaluate.mountYawCrosstalk(1);
        assertTrue(crosstalk.contains("| 30 | learned (nod) | 1/1 |"), crosstalk);
        String acceptance = Evaluate.axisFalseAcceptance(1);
        assertTrue(acceptance.contains("| ear to shoulder 20° (sideways) | 0/1 | 1/1 | 0/1 | - |"), acceptance);
        assertTrue(acceptance.contains("| head turns only (every ~2 s, up to 45°) | 0/1 | 0/1 | 1/1 | - |"), acceptance);
        String quantile = Evaluate.calibrationQuantile(1);
        assertTrue(quantile.contains("| one 1 s fidget to 20° | accepted | 0/1 | 0/1 | 1/1"), quantile);
        assertTrue(Evaluate.nodLineFitComparison(1).startsWith("| sway std"));
        assertTrue(Evaluate.nodCalibrationSuccess(1).contains("20° nod: accepted / neutral ok"));
    }

    @Test
    void medianOfEvenAndOddLists() {
        assertEquals(2.0, Evaluate.median(List.of(3.0, 1.0, 2.0)));
        assertEquals(2.5, Evaluate.median(List.of(4.0, 1.0, 2.0, 3.0)));
        assertTrue(Double.isNaN(Evaluate.median(List.of())));
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
