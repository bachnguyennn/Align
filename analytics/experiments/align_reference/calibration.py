"""Neutral-baseline calibration."""

from __future__ import annotations

from dataclasses import dataclass
from typing import List, Optional

from .geometry import Vec3, ZERO, add, angle_between_degrees, length, normalized
from .model import (
    INSUFFICIENT_SAMPLES,
    TIME_EPSILON,
    TOO_MUCH_MOVEMENT,
    PostureConfiguration,
)


@dataclass(frozen=True)
class CalibrationStep:
    """Result of feeding one sample: in progress, succeeded (mean gravity), or failed."""

    finished: bool
    progress: float
    mean_gravity: Optional[Vec3] = None
    sample_count: int = 0
    failure: Optional[str] = None


class CalibrationService:
    """Collects `calibration_duration` seconds of smoothed gravity, measured from the first
    sample it receives. Baseline = normalized mean. Fails with insufficientSamples if fewer than
    `minimum_calibration_samples` were collected, else with tooMuchMovement if any sample is more
    than `calibration_max_spread_degrees` from the mean."""

    def __init__(self) -> None:
        self.is_active = False
        self.start_timestamp: Optional[float] = None
        self.last_timestamp: Optional[float] = None
        self.samples: List[Vec3] = []

    def begin(self) -> None:
        self.is_active = True
        self.start_timestamp = None
        self.last_timestamp = None
        self.samples = []

    def cancel(self) -> None:
        self.is_active = False
        self.start_timestamp = None
        self.last_timestamp = None
        self.samples = []

    def progress(self, duration: float) -> float:
        if not self.is_active or self.start_timestamp is None or self.last_timestamp is None:
            return 0.0
        if duration <= 0.0:
            return 1.0
        p = (self.last_timestamp - self.start_timestamp) / duration
        return min(1.0, max(0.0, p))

    def add(self, gravity_unit: Vec3, timestamp: float, config: PostureConfiguration) -> CalibrationStep:
        if self.start_timestamp is None:
            self.start_timestamp = timestamp
        self.last_timestamp = timestamp
        self.samples.append(gravity_unit)
        elapsed = timestamp - self.start_timestamp
        duration = config.calibration_duration
        if elapsed + TIME_EPSILON < duration:
            return CalibrationStep(finished=False, progress=self.progress(duration))

        samples = self.samples
        self.cancel()
        count = len(samples)
        if count < config.minimum_calibration_samples:
            return CalibrationStep(finished=True, progress=1.0, sample_count=count, failure=INSUFFICIENT_SAMPLES)
        total = ZERO
        for g in samples:
            total = add(total, g)
        mean = normalized(total)
        if length(mean) == 0.0:
            return CalibrationStep(finished=True, progress=1.0, sample_count=count, failure=TOO_MUCH_MOVEMENT)
        limit = config.calibration_max_spread_degrees
        for g in samples:
            if angle_between_degrees(g, mean) > limit:
                return CalibrationStep(finished=True, progress=1.0, sample_count=count, failure=TOO_MUCH_MOVEMENT)
        return CalibrationStep(finished=True, progress=1.0, mean_gravity=mean, sample_count=count)
