package com.bachnguyennn.align.reference;

/**
 * AlignCore {@code TiltDirection}. Declaration order is the fixed evaluation order for direction
 * precedence (the first wins on an exact ratio tie), Python {@code DIRECTION_ORDER}.
 */
public enum TiltDirection {
    FORWARD("forward"),
    BACKWARD("backward"),
    LEFT("left"),
    RIGHT("right");

    private final String rawValue;

    TiltDirection(String rawValue) {
        this.rawValue = rawValue;
    }

    /** The Swift raw value, as used in fixture JSON. */
    public String rawValue() {
        return rawValue;
    }

    public static TiltDirection fromRawValue(String rawValue) {
        for (TiltDirection d : values()) {
            if (d.rawValue.equals(rawValue)) {
                return d;
            }
        }
        throw new IllegalArgumentException("unknown tilt direction: " + rawValue);
    }

    @Override
    public String toString() {
        return rawValue;
    }
}
