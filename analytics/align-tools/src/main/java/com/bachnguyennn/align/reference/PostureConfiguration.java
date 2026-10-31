package com.bachnguyennn.align.reference;

import com.bachnguyennn.align.reference.Geometry.Vec3;
import com.fasterxml.jackson.databind.JsonNode;
import java.util.Map;
import java.util.function.Consumer;

/**
 * Mirrors AlignCore {@code PostureConfiguration} defaults exactly. {@code maxProcessingRateHz} is
 * null when there is no cap.
 *
 * <p>D-017: {@code calibrationSpreadQuantile} (fraction of neutral-calibration samples that must
 * lie within {@code calibrationMaxSpreadDegrees} of the mean; 1.0 = v1 rule) and the guided-nod
 * axis calibration parameters {@code axisCalibration*}.
 */
public record PostureConfiguration(
        double calibrationDuration,
        double calibrationMaxSpreadDegrees,
        double calibrationSpreadQuantile,
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
        HeadAxisConvention axes,
        double axisCalibrationDuration,
        double axisCalibrationMinimumNodDegrees,
        double axisCalibrationMaxYawDegrees,
        double axisCalibrationMaxOffAxisRatio) {

    /** {@code PostureConfiguration.default}. */
    public static final PostureConfiguration DEFAULT = new Builder().build();

    /** Fixture JSON (= Swift property) names of the scalar fields, besides forwardAxis/lateralAxis. */
    private static final Map<String, Setter> CONFIG_KEYS = Map.ofEntries(
            Map.entry("calibrationDuration", (b, v) -> b.calibrationDuration(v.asDouble())),
            Map.entry("calibrationMaxSpreadDegrees", (b, v) -> b.calibrationMaxSpreadDegrees(v.asDouble())),
            Map.entry("calibrationSpreadQuantile", (b, v) -> b.calibrationSpreadQuantile(v.asDouble())),
            Map.entry("minimumCalibrationSamples", (b, v) -> b.minimumCalibrationSamples(v.asInt())),
            Map.entry("forwardThresholdDegrees", (b, v) -> b.forwardThresholdDegrees(v.asDouble())),
            Map.entry("backwardThresholdDegrees", (b, v) -> b.backwardThresholdDegrees(v.asDouble())),
            Map.entry("lateralThresholdDegrees", (b, v) -> b.lateralThresholdDegrees(v.asDouble())),
            Map.entry("hysteresisDegrees", (b, v) -> b.hysteresisDegrees(v.asDouble())),
            Map.entry("sustainedDuration", (b, v) -> b.sustainedDuration(v.asDouble())),
            Map.entry("reminderCooldown", (b, v) -> b.reminderCooldown(v.asDouble())),
            Map.entry("smoothingTimeConstant", (b, v) -> b.smoothingTimeConstant(v.asDouble())),
            Map.entry("maxProcessingRateHz", (b, v) -> b.maxProcessingRateHz(v.isNull() ? null : v.asDouble())),
            Map.entry("maxSampleGap", (b, v) -> b.maxSampleGap(v.asDouble())),
            Map.entry("axisCalibrationDuration", (b, v) -> b.axisCalibrationDuration(v.asDouble())),
            Map.entry("axisCalibrationMinimumNodDegrees", (b, v) -> b.axisCalibrationMinimumNodDegrees(v.asDouble())),
            Map.entry("axisCalibrationMaxYawDegrees", (b, v) -> b.axisCalibrationMaxYawDegrees(v.asDouble())),
            Map.entry("axisCalibrationMaxOffAxisRatio", (b, v) -> b.axisCalibrationMaxOffAxisRatio(v.asDouble())));

    private interface Setter {
        void apply(Builder builder, JsonNode value);
    }

    /** True if {@code key} is a fixture configuration key (a scalar field or forwardAxis/lateralAxis). */
    public static boolean isKey(String key) {
        return CONFIG_KEYS.containsKey(key) || key.equals("forwardAxis") || key.equals("lateralAxis");
    }

    /** Builds a configuration from fixture-style camelCase overrides (null or empty = default). */
    public static PostureConfiguration fromOverrides(JsonNode overrides) {
        if (overrides == null || overrides.isNull() || overrides.isEmpty()) {
            return DEFAULT;
        }
        return DEFAULT.withOverrides(overrides);
    }

    /** A copy with fixture-style camelCase overrides applied (unknown keys are an error). */
    public PostureConfiguration withOverrides(JsonNode overrides) {
        if (overrides == null || overrides.isNull() || overrides.isEmpty()) {
            return this;
        }
        Builder builder = new Builder(this);
        Vec3 forwardAxis = axes.forwardAxis();
        Vec3 lateralAxis = axes.lateralAxis();
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
        private double calibrationSpreadQuantile = 0.9;
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
        private double axisCalibrationDuration = 8.0;
        private double axisCalibrationMinimumNodDegrees = 12.0;
        private double axisCalibrationMaxYawDegrees = 45.0;
        private double axisCalibrationMaxOffAxisRatio = 0.35;

        private Builder() {}

        private Builder(PostureConfiguration c) {
            calibrationDuration = c.calibrationDuration;
            calibrationMaxSpreadDegrees = c.calibrationMaxSpreadDegrees;
            calibrationSpreadQuantile = c.calibrationSpreadQuantile;
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
            axisCalibrationDuration = c.axisCalibrationDuration;
            axisCalibrationMinimumNodDegrees = c.axisCalibrationMinimumNodDegrees;
            axisCalibrationMaxYawDegrees = c.axisCalibrationMaxYawDegrees;
            axisCalibrationMaxOffAxisRatio = c.axisCalibrationMaxOffAxisRatio;
        }

        public Builder calibrationDuration(double v) { calibrationDuration = v; return this; }
        public Builder calibrationMaxSpreadDegrees(double v) { calibrationMaxSpreadDegrees = v; return this; }
        public Builder calibrationSpreadQuantile(double v) { calibrationSpreadQuantile = v; return this; }
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
        public Builder axisCalibrationDuration(double v) { axisCalibrationDuration = v; return this; }
        public Builder axisCalibrationMinimumNodDegrees(double v) { axisCalibrationMinimumNodDegrees = v; return this; }
        public Builder axisCalibrationMaxYawDegrees(double v) { axisCalibrationMaxYawDegrees = v; return this; }
        public Builder axisCalibrationMaxOffAxisRatio(double v) { axisCalibrationMaxOffAxisRatio = v; return this; }

        public PostureConfiguration build() {
            return new PostureConfiguration(calibrationDuration, calibrationMaxSpreadDegrees,
                    calibrationSpreadQuantile, minimumCalibrationSamples, forwardThresholdDegrees,
                    backwardThresholdDegrees, lateralThresholdDegrees, hysteresisDegrees, sustainedDuration,
                    reminderCooldown, smoothingTimeConstant, maxProcessingRateHz, maxSampleGap, axes,
                    axisCalibrationDuration, axisCalibrationMinimumNodDegrees, axisCalibrationMaxYawDegrees,
                    axisCalibrationMaxOffAxisRatio);
        }
    }
}
