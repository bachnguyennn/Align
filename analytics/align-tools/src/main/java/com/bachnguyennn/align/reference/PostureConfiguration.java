package com.bachnguyennn.align.reference;

import com.bachnguyennn.align.reference.Geometry.Vec3;
import com.fasterxml.jackson.databind.JsonNode;
import java.util.Map;
import java.util.function.Consumer;

/**
 * Mirrors AlignCore {@code PostureConfiguration} defaults exactly. {@code maxProcessingRateHz} is
 * null when there is no cap.
 */
public record PostureConfiguration(
        double calibrationDuration,
        double calibrationMaxSpreadDegrees,
        int minimumCalibrationSamples,
        double forwardThresholdDegrees,
        double backwardThresholdDegrees,
        double lateralThresholdDegrees,
        double hysteresisDegrees,
        double sustainedDuration,
        double reminderCooldown,
        double smoothingTimeConstant,
        Double maxProcessingRateHz,
        double maxSampleGap,
        HeadAxisConvention axes) {

    /** {@code PostureConfiguration.default}. */
    public static final PostureConfiguration DEFAULT = new Builder().build();

    /** Fixture JSON (= Swift property) names of the scalar fields, besides forwardAxis/lateralAxis. */
    private static final Map<String, Setter> CONFIG_KEYS = Map.ofEntries(
            Map.entry("calibrationDuration", (b, v) -> b.calibrationDuration(v.asDouble())),
            Map.entry("calibrationMaxSpreadDegrees", (b, v) -> b.calibrationMaxSpreadDegrees(v.asDouble())),
            Map.entry("minimumCalibrationSamples", (b, v) -> b.minimumCalibrationSamples(v.asInt())),
            Map.entry("forwardThresholdDegrees", (b, v) -> b.forwardThresholdDegrees(v.asDouble())),
            Map.entry("backwardThresholdDegrees", (b, v) -> b.backwardThresholdDegrees(v.asDouble())),
            Map.entry("lateralThresholdDegrees", (b, v) -> b.lateralThresholdDegrees(v.asDouble())),
            Map.entry("hysteresisDegrees", (b, v) -> b.hysteresisDegrees(v.asDouble())),
            Map.entry("sustainedDuration", (b, v) -> b.sustainedDuration(v.asDouble())),
            Map.entry("reminderCooldown", (b, v) -> b.reminderCooldown(v.asDouble())),
            Map.entry("smoothingTimeConstant", (b, v) -> b.smoothingTimeConstant(v.asDouble())),
            Map.entry("maxProcessingRateHz", (b, v) -> b.maxProcessingRateHz(v.isNull() ? null : v.asDouble())),
            Map.entry("maxSampleGap", (b, v) -> b.maxSampleGap(v.asDouble())));

    private interface Setter {
        void apply(Builder builder, JsonNode value);
    }

    /** Builds a configuration from fixture-style camelCase overrides (null or empty = default). */
    public static PostureConfiguration fromOverrides(JsonNode overrides) {
        if (overrides == null || overrides.isNull() || overrides.isEmpty()) {
            return DEFAULT;
        }
        Builder builder = new Builder();
        Vec3 forwardAxis = HeadAxisConvention.DEFAULT.forwardAxis();
        Vec3 lateralAxis = HeadAxisConvention.DEFAULT.lateralAxis();
        for (Map.Entry<String, JsonNode> entry : overrides.properties()) {
            String key = entry.getKey();
            JsonNode value = entry.getValue();
            if (key.equals("forwardAxis")) {
                forwardAxis = vec3(value);
            } else if (key.equals("lateralAxis")) {
                lateralAxis = vec3(value);
            } else if (CONFIG_KEYS.containsKey(key)) {
                CONFIG_KEYS.get(key).apply(builder, value);
            } else {
                throw new IllegalArgumentException("unknown configuration override: " + key);
            }
        }
        return builder.axes(new HeadAxisConvention(forwardAxis, lateralAxis)).build();
    }

    private static Vec3 vec3(JsonNode value) {
        return new Vec3(value.get(0).asDouble(), value.get(1).asDouble(), value.get(2).asDouble());
    }

    /** A copy with the given changes, e.g. {@code c.replacing(b -> b.hysteresisDegrees(1.0))}. */
    public PostureConfiguration replacing(Consumer<Builder> changes) {
        Builder builder = new Builder(this);
        changes.accept(builder);
        return builder.build();
    }

    public static Builder builder() {
        return new Builder();
    }

    /** Mutable builder starting from the defaults. */
    public static final class Builder {
        private double calibrationDuration = 10.0;
        private double calibrationMaxSpreadDegrees = 5.0;
        private int minimumCalibrationSamples = 100;
        private double forwardThresholdDegrees = 15.0;
        private double backwardThresholdDegrees = 20.0;
        private double lateralThresholdDegrees = 15.0;
        private double hysteresisDegrees = 3.0;
        private double sustainedDuration = 30.0;
        private double reminderCooldown = 300.0;
        private double smoothingTimeConstant = 0.5;
        private Double maxProcessingRateHz = null;
        private double maxSampleGap = 1.0;
        private HeadAxisConvention axes = HeadAxisConvention.DEFAULT;

        private Builder() {}

        private Builder(PostureConfiguration c) {
            calibrationDuration = c.calibrationDuration;
            calibrationMaxSpreadDegrees = c.calibrationMaxSpreadDegrees;
            minimumCalibrationSamples = c.minimumCalibrationSamples;
            forwardThresholdDegrees = c.forwardThresholdDegrees;
            backwardThresholdDegrees = c.backwardThresholdDegrees;
            lateralThresholdDegrees = c.lateralThresholdDegrees;
            hysteresisDegrees = c.hysteresisDegrees;
            sustainedDuration = c.sustainedDuration;
            reminderCooldown = c.reminderCooldown;
            smoothingTimeConstant = c.smoothingTimeConstant;
            maxProcessingRateHz = c.maxProcessingRateHz;
            maxSampleGap = c.maxSampleGap;
            axes = c.axes;
        }

        public Builder calibrationDuration(double v) { calibrationDuration = v; return this; }
        public Builder calibrationMaxSpreadDegrees(double v) { calibrationMaxSpreadDegrees = v; return this; }
        public Builder minimumCalibrationSamples(int v) { minimumCalibrationSamples = v; return this; }
        public Builder forwardThresholdDegrees(double v) { forwardThresholdDegrees = v; return this; }
        public Builder backwardThresholdDegrees(double v) { backwardThresholdDegrees = v; return this; }
        public Builder lateralThresholdDegrees(double v) { lateralThresholdDegrees = v; return this; }
        public Builder hysteresisDegrees(double v) { hysteresisDegrees = v; return this; }
        public Builder sustainedDuration(double v) { sustainedDuration = v; return this; }
        public Builder reminderCooldown(double v) { reminderCooldown = v; return this; }
        public Builder smoothingTimeConstant(double v) { smoothingTimeConstant = v; return this; }
        public Builder maxProcessingRateHz(Double v) { maxProcessingRateHz = v; return this; }
        public Builder maxSampleGap(double v) { maxSampleGap = v; return this; }
        public Builder axes(HeadAxisConvention v) { axes = v; return this; }

        public PostureConfiguration build() {
            return new PostureConfiguration(calibrationDuration, calibrationMaxSpreadDegrees,
                    minimumCalibrationSamples, forwardThresholdDegrees, backwardThresholdDegrees,
                    lateralThresholdDegrees, hysteresisDegrees, sustainedDuration, reminderCooldown,
                    smoothingTimeConstant, maxProcessingRateHz, maxSampleGap, axes);
        }
    }
}
