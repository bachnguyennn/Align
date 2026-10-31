"""Time-constant exponential smoothing of the head-frame gravity unit vector."""

from __future__ import annotations

import math
from typing import Optional

from .geometry import Vec3, add, length, normalized, scale, sub


class MotionFilter:
    """EMA with alpha = 1 - exp(-dt / tau), renormalized to a unit vector.

    Being time-based (not per-sample), the response is the same at any sample rate.
    The first sample after construction or `reset()` initializes the output.
    """

    def __init__(self) -> None:
        self.value: Optional[Vec3] = None
        self.last_timestamp: Optional[float] = None

    def reset(self) -> None:
        self.value = None
        self.last_timestamp = None

    def update(self, gravity_unit: Vec3, timestamp: float, time_constant: float) -> Vec3:
        if self.value is None or self.last_timestamp is None:
            self.value = gravity_unit
            self.last_timestamp = timestamp
            return gravity_unit
        dt = timestamp - self.last_timestamp
        if dt < 0.0:
            dt = 0.0
        if time_constant <= 0.0:
            alpha = 1.0
        else:
            alpha = 1.0 - math.exp(-dt / time_constant)
        blended = add(self.value, scale(sub(gravity_unit, self.value), alpha))
        result = normalized(blended)
        if length(result) == 0.0:
            result = gravity_unit
        self.value = result
        self.last_timestamp = timestamp
        return result
