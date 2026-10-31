"""Reminder cooldown policy."""

from __future__ import annotations

from typing import Optional

from .model import TIME_EPSILON, ReminderDecision


class ReminderDecisionEngine:
    """Called once per episode, on the update where the tilt becomes sustained. Returns a
    reminder if no reminder was given yet, or at least `cooldown` seconds have passed since the
    last one. A timestamp earlier than the last reminder (clock base changed) also allows one."""

    def __init__(self) -> None:
        self.last_reminder_timestamp: Optional[float] = None

    def reset(self) -> None:
        self.last_reminder_timestamp = None

    def evaluate(
        self,
        timestamp: float,
        direction: str,
        deviation_degrees: float,
        sustained_seconds: float,
        cooldown: float,
    ) -> Optional[ReminderDecision]:
        last = self.last_reminder_timestamp
        if last is not None and timestamp >= last and timestamp - last + TIME_EPSILON < cooldown:
            return None
        self.last_reminder_timestamp = timestamp
        return ReminderDecision(
            timestamp=timestamp,
            direction=direction,
            deviation_degrees=deviation_degrees,
            sustained_seconds=sustained_seconds,
        )
