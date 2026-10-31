package com.bachnguyennn.align.reference;

import java.math.BigDecimal;
import java.math.RoundingMode;

/**
 * Python's float rounding and formatting, so that fixtures, reference blocks and evaluation
 * tables written by Java are identical to the Python ones for the same values.
 *
 * <p>Python rounds the exact binary value of a double (half-even only on exact ties), which is
 * what {@code new BigDecimal(double)} with {@link RoundingMode#HALF_EVEN} does. Java's
 * {@code String.format("%.2f")} rounds half-up on the shortest decimal instead (e.g. 2.675 →
 * "2.68" where Python gives "2.67"), so it is not used.
 */
public final class PythonFormat {

    private PythonFormat() {}

    /** Python {@code round(x, digits)}. */
    public static double round(double x, int digits) {
        if (!Double.isFinite(x) || x == 0.0) {
            return x;
        }
        double r = new BigDecimal(x).setScale(digits, RoundingMode.HALF_EVEN).doubleValue();
        // Python keeps the sign of a value that rounds to zero (round(-0.00001, 2) == -0.0).
        return r == 0.0 ? StrictMath.copySign(0.0, x) : r;
    }

    /** Python {@code f"{x:.{digits}f}"}, including "-0.000" for tiny negative values. */
    public static String fixed(double x, int digits) {
        if (Double.isNaN(x)) {
            return "nan";
        }
        if (Double.isInfinite(x)) {
            return x > 0 ? "inf" : "-inf";
        }
        String sign = (Double.doubleToRawLongBits(x) < 0) ? "-" : "";
        String body = new BigDecimal(Math.abs(x)).setScale(digits, RoundingMode.HALF_EVEN).toPlainString();
        return sign + body;
    }

    /**
     * Python {@code repr(float)}: the shortest string that round-trips, in fixed notation when the
     * decimal exponent is in [-4, 16), otherwise in scientific notation ("1e-05", "1.5e+16").
     * Relies on {@link Double#toString(double)} producing the shortest digits (JDK 19+).
     */
    public static String repr(double x) {
        if (Double.isNaN(x)) {
            return "NaN";
        }
        if (Double.isInfinite(x)) {
            return x > 0 ? "Infinity" : "-Infinity";
        }
        if (x == 0.0) {
            return (Double.doubleToRawLongBits(x) < 0) ? "-0.0" : "0.0";
        }
        BigDecimal shortest = new BigDecimal(Double.toString(Math.abs(x))).stripTrailingZeros();
        String digits = shortest.unscaledValue().toString();
        int exponent = digits.length() - shortest.scale() - 1;  // decimal exponent of the first digit
        StringBuilder out = new StringBuilder(x < 0 ? "-" : "");
        if (exponent >= -4 && exponent < 16) {
            if (exponent >= 0) {
                if (digits.length() <= exponent + 1) {
                    out.append(digits).append("0".repeat(exponent + 1 - digits.length())).append(".0");
                } else {
                    out.append(digits, 0, exponent + 1).append('.').append(digits.substring(exponent + 1));
                }
            } else {
                out.append("0.").append("0".repeat(-exponent - 1)).append(digits);
            }
        } else {
            out.append(digits.charAt(0));
            if (digits.length() > 1) {
                out.append('.').append(digits.substring(1));
            }
            out.append('e').append(exponent < 0 ? '-' : '+');
            String e = Integer.toString(Math.abs(exponent));
            out.append(e.length() < 2 ? "0" + e : e);
        }
        return out.toString();
    }
}
