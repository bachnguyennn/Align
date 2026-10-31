"""Posture state machine: neutral -> deviating -> sustainedTilt -> neutral."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

from .model import (
    BACKWARD,
    DEVIATING,
    DIRECTION_ORDER,
    FORWARD,
    LEFT,
    NEUTRAL,
    RIGHT,
    SUSTAINED_TILT,
    TIME_EPSILON,
    PostureConfiguration,
    PostureEpisode,
    PostureState,
    TiltEstimate,
)

PHASE_NEUTRAL = 0
PHASE_DEVIATING = 1
PHASE_SUSTAINED = 2

# Thresholds at or below this are treated as this value (avoids division by zero).
MINIMUM_THRESHOLD_DEGREES = 1e-6


def component_degrees(tilt: TiltEstimate, direction: str) -> float:
    """Signed tilt in `direction`: positive means tilted that way."""
    if direction == FORWARD:
        return tilt.forward_degrees
    if direction == BACKWARD:
        return -tilt.forward_degrees
    if direction == RIGHT:
        return tilt.lateral_degrees
    return -tilt.lateral_degrees  # LEFT


def threshold_degrees(direction: str, config: PostureConfiguration) -> float:
    if direction == FORWARD:
        t = config.forward_threshold_degrees
    elif direction == BACKWARD:
        t = config.backward_threshold_degrees
    else:
        t = config.lateral_threshold_degrees
    return max(t, MINIMUM_THRESHOLD_DEGREES)


def dominant_direction(tilt: TiltEstimate, config: PostureConfiguration) -> Optional[str]:
    """Direction whose |angle| / threshold ratio is largest among those at or over threshold."""
    best = None
    best_ratio = 0.0
    for direction in DIRECTION_ORDER:
        ratio = component_degrees(tilt, direction) / threshold_degrees(direction, config)
        if ratio >= 1.0 and ratio > best_ratio:
            best = direction
            best_ratio = ratio
    return best


@dataclass(frozen=True)
class DetectorOutput:
    state: PostureState
    became_sustained: bool = False
    completed_episode: Optional[PostureEpisode] = None


class PostureDetector:
    """Rules (applied to the smoothed tilt of each processed sample):

    - neutral -> deviating(d) when some direction's component reaches its threshold; d is the
      direction with the largest component/threshold ratio. The direction is then locked for the
      rest of that deviation (no mid-episode switching, which avoids flicker).
    - deviating -> sustainedTilt once `sustained_duration` has elapsed since onset.
    - deviating/sustained -> neutral once d's component drops below threshold - hysteresis. If
      another direction is over its own threshold on that sample, a new deviation starts there.
    - Leaving sustainedTilt (or `interrupt`) produces a PostureEpisode.
    """

    def __init__(self) -> None:
        self.phase = PHASE_NEUTRAL
        self.direction: Optional[str] = None
        self.since: Optional[float] = None
        self.peak = 0.0
        self.reminder_triggered = False

    def reset(self) -> None:
        self.phase = PHASE_NEUTRAL
        self.direction = None
        self.since = None
        self.peak = 0.0
        self.reminder_triggered = False

    @property
    def state(self) -> PostureState:
        if self.phase == PHASE_DEVIATING:
            return PostureState(DEVIATING, direction=self.direction, since=self.since)
        if self.phase == PHASE_SUSTAINED:
            return PostureState(SUSTAINED_TILT, direction=self.direction, since=self.since)
        return PostureState(NEUTRAL)

    def mark_reminder_triggered(self) -> None:
        self.reminder_triggered = True

    def _episode(self, end_timestamp: float) -> PostureEpisode:
        return PostureEpisode(
            direction=self.direction,
            start_timestamp=self.since,
            end_timestamp=end_timestamp,
            peak_deviation_degrees=self.peak,
            reminder_triggered=self.reminder_triggered,
        )

    def interrupt(self, at: float) -> Optional[PostureEpisode]:
        """Closes a sustained episode (if any) at `at` and resets to neutral."""
        episode = self._episode(at) if self.phase == PHASE_SUSTAINED else None
        self.reset()
        return episode

    def update(self, tilt: TiltEstimate, config: PostureConfiguration) -> DetectorOutput:
        t = tilt.timestamp
        completed = None
        became_sustained = False

        if self.phase != PHASE_NEUTRAL:
            value = component_degrees(tilt, self.direction)
            release = threshold_degrees(self.direction, config) - config.hysteresis_degrees
            if value < release:
                if self.phase == PHASE_SUSTAINED:
                    completed = self._episode(t)
                self.reset()
            else:
                if value > self.peak:
                    self.peak = value
                if self.phase == PHASE_DEVIATING and t - self.since + TIME_EPSILON >= config.sustained_duration:
                    self.phase = PHASE_SUSTAINED
                    became_sustained = True

        if self.phase == PHASE_NEUTRAL:
            direction = dominant_direction(tilt, config)
            if direction is not None:
                self.phase = PHASE_DEVIATING
                self.direction = direction
                self.since = t
                self.peak = component_degrees(tilt, direction)
                self.reminder_triggered = False
                if config.sustained_duration <= TIME_EPSILON:
                    self.phase = PHASE_SUSTAINED
                    became_sustained = True

        return DetectorOutput(self.state, became_sustained, completed)
