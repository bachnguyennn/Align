"""Python mirrors of the AlignCore contract types used by the pipeline."""

from __future__ import annotations

from dataclasses import dataclass, field, fields
from typing import Optional

from .geometry import Quat, Vec3

# TiltDirection raw values (AlignCore `TiltDirection`).
FORWARD = "forward"
BACKWARD = "backward"
LEFT = "left"
RIGHT = "right"
# Fixed evaluation order for direction precedence (the first wins on an exact ratio tie).
DIRECTION_ORDER = (FORWARD, BACKWARD, LEFT, RIGHT)

# CalibrationFailure raw values.
TOO_MUCH_MOVEMENT = "tooMuchMovement"
INSUFFICIENT_SAMPLES = "insufficientSamples"
SENSOR_INTERRUPTED = "sensorInterrupted"

# PostureState case names.
UNAVAILABLE = "unavailable"
NEEDS_CALIBRATION = "needsCalibration"
CALIBRATING = "calibrating"
NEUTRAL = "neutral"
DEVIATING = "deviating"
SUSTAINED_TILT = "sustainedTilt"

# Tolerance used when comparing elapsed times with durations, so that e.g. 45.04 - 15.04
# (= 29.999999999999996 in IEEE doubles) counts as 30 s. Identical constant in Swift.
TIME_EPSILON = 1e-9


@dataclass(frozen=True)
class MotionSample:
    timestamp: float
    attitude: Quat
    gravity: Optional[Vec3] = None
    rotation_rate: Optional[Vec3] = None


@dataclass(frozen=True)
class TiltEstimate:
    timestamp: float
    forward_degrees: float
    lateral_degrees: float
    total_degrees: float


@dataclass(frozen=True)
class PostureState:
    kind: str
    progress: Optional[float] = None
    direction: Optional[str] = None
    since: Optional[float] = None


@dataclass(frozen=True)
class NeutralBaseline:
    gravity: Vec3
    captured_at: float
    sample_count: int
    version: int


@dataclass(frozen=True)
class CalibrationOutcome:
    """`succeeded` carries the baseline; otherwise `failure` is a CalibrationFailure raw value."""

    succeeded: bool
    baseline: Optional[NeutralBaseline] = None
    failure: Optional[str] = None

    @property
    def name(self) -> str:
        return "succeeded" if self.succeeded else str(self.failure)


@dataclass(frozen=True)
class ReminderDecision:
    timestamp: float
    direction: str
    deviation_degrees: float
    sustained_seconds: float


@dataclass(frozen=True)
class PostureEpisode:
    direction: str
    start_timestamp: float
    end_timestamp: float
    peak_deviation_degrees: float
    reminder_triggered: bool


@dataclass(frozen=True)
class PostureUpdate:
    timestamp: float
    state: PostureState
    tilt: Optional[TiltEstimate] = None
    reminder: Optional[ReminderDecision] = None
    completed_episode: Optional[PostureEpisode] = None
    calibration_outcome: Optional[CalibrationOutcome] = None


@dataclass(frozen=True)
class HeadAxisConvention:
    forward_axis: Vec3 = Vec3(1.0, 0.0, 0.0)
    lateral_axis: Vec3 = Vec3(0.0, 1.0, 0.0)


# camelCase (Swift / fixture JSON) -> snake_case (Python) names of PostureConfiguration fields.
CONFIG_KEYS = {
    "calibrationDuration": "calibration_duration",
    "calibrationMaxSpreadDegrees": "calibration_max_spread_degrees",
    "minimumCalibrationSamples": "minimum_calibration_samples",
    "forwardThresholdDegrees": "forward_threshold_degrees",
    "backwardThresholdDegrees": "backward_threshold_degrees",
    "lateralThresholdDegrees": "lateral_threshold_degrees",
    "hysteresisDegrees": "hysteresis_degrees",
    "sustainedDuration": "sustained_duration",
    "reminderCooldown": "reminder_cooldown",
    "smoothingTimeConstant": "smoothing_time_constant",
    "maxProcessingRateHz": "max_processing_rate_hz",
    "maxSampleGap": "max_sample_gap",
}


@dataclass(frozen=True)
class PostureConfiguration:
    """Mirrors AlignCore `PostureConfiguration` defaults exactly."""

    calibration_duration: float = 10.0
    calibration_max_spread_degrees: float = 5.0
    minimum_calibration_samples: int = 100
    forward_threshold_degrees: float = 15.0
    backward_threshold_degrees: float = 20.0
    lateral_threshold_degrees: float = 15.0
    hysteresis_degrees: float = 3.0
    sustained_duration: float = 30.0
    reminder_cooldown: float = 300.0
    smoothing_time_constant: float = 0.5
    max_processing_rate_hz: Optional[float] = None
    max_sample_gap: float = 1.0
    axes: HeadAxisConvention = field(default_factory=HeadAxisConvention)

    @staticmethod
    def from_overrides(overrides: Optional[dict]) -> "PostureConfiguration":
        """Builds a configuration from fixture-style camelCase overrides."""
        if not overrides:
            return PostureConfiguration()
        kwargs = {}
        forward_axis = Vec3(1.0, 0.0, 0.0)
        lateral_axis = Vec3(0.0, 1.0, 0.0)
        for key, value in overrides.items():
            if key == "forwardAxis":
                forward_axis = Vec3(*[float(c) for c in value])
            elif key == "lateralAxis":
                lateral_axis = Vec3(*[float(c) for c in value])
            elif key in CONFIG_KEYS:
                kwargs[CONFIG_KEYS[key]] = value
            else:
                raise KeyError(f"unknown configuration override: {key}")
        kwargs["axes"] = HeadAxisConvention(forward_axis, lateral_axis)
        return PostureConfiguration(**kwargs)

    def replacing(self, **changes) -> "PostureConfiguration":
        values = {f.name: getattr(self, f.name) for f in fields(self)}
        values.update(changes)
        return PostureConfiguration(**values)
