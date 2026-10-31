package com.bachnguyennn.align.reference;

import static org.junit.jupiter.api.Assertions.assertEquals;

import com.fasterxml.jackson.databind.node.ObjectNode;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

/** Python-compatible rounding, formatting and JSON layout (expected values taken from CPython 3.12). */
class PythonFormatTest {

    @ParameterizedTest(name = "repr({0}) = {1}")
    @CsvSource({
            "0.0, 0.0", "-0.0, -0.0", "1.0, 1.0", "-0.076, -0.076", "5000.0, 5000.0", "0.1, 0.1",
            "51.96, 51.96", "1e-05, 1e-05", "0.0001, 0.0001", "0.00012, 0.00012", "1.5e-07, 1.5e-07",
            "123456789012345.6, 123456789012345.6", "1e+16, 1e+16", "1.2345e+20, 1.2345e+20",
            "0.30000000000000004, 0.30000000000000004", "29.999999999999996, 29.999999999999996"})
    void reprMatchesPython(double x, String expected) {
        assertEquals(expected, PythonFormat.repr(x));
    }

    @ParameterizedTest(name = "round({0}, {1}) = {2}")
    @CsvSource({
            "2.675, 2, 2.67", "0.125, 2, 0.12", "0.375, 2, 0.38", "51.959999, 2, 51.96",
            "5025.24004, 4, 5025.24", "-0.00001, 2, -0.0", "1.23456789, 4, 1.2346"})
    void roundMatchesPython(double x, int digits, double expected) {
        assertEquals(expected, PythonFormat.round(x, digits));
        assertEquals(Double.doubleToRawLongBits(expected), Double.doubleToRawLongBits(PythonFormat.round(x, digits)));
    }

    /** {@code f"{x:.{digits}f}"}. */
    @ParameterizedTest(name = "fixed({0}, {1}) = {2}")
    @CsvSource({
            "2.675, 2, 2.67", "0.125, 2, 0.12", "-1e-12, 3, -0.000", "0.0, 3, 0.000", "-0.0, 1, -0.0",
            "15.0, 0, 15", "0.5, 0, 0", "1.5, 0, 2", "-0.3036, 3, -0.304", "38.4, 0, 38"})
    void fixedMatchesPython(double x, int digits, String expected) {
        assertEquals(expected, PythonFormat.fixed(x, digits));
    }

    @Test
    void jsonLayoutMatchesPythonDumps() {
        ObjectNode o = Json.object();
        o.put("a", 1);
        o.put("b", 2.0);
        o.putArray("c");
        o.putObject("d");
        o.putArray("e").add(0.5).add(true).addNull();
        o.put("s", "x\"y\\zé");
        // json.dumps(o, indent=2) and json.dumps(o, separators=(",", ":"))
        assertEquals("{\n  \"a\": 1,\n  \"b\": 2.0,\n  \"c\": [],\n  \"d\": {},\n  \"e\": [\n    0.5,\n    true,\n"
                + "    null\n  ],\n  \"s\": \"x\\\"y\\\\z\\u00e9\"\n}", Json.dumps(o, 2));
        assertEquals("{\"a\":1,\"b\":2.0,\"c\":[],\"d\":{},\"e\":[0.5,true,null],\"s\":\"x\\\"y\\\\z\\u00e9\"}",
                Json.dumpsCompact(o));
    }
}
