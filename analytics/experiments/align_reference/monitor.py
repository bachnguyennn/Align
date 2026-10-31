"""PostureMonitor: the full per-sample pipeline. Mirrors Swift `PostureMonitor`.

Per sample:
 1. Validate: gravity (or, if missing, gravity derived from the attitude) must be non-zero;
    timestamps must strictly increase. Invalid samples are ignored (passive update).
 2. Gap check: if the gap to the previous received sample exceeds `max_sample_gap`, act like
    `interrupt(at: previous timestamp)` and then process this sample from a fresh state.
 3. Decimation by `max_processing_rate_hz` (phase-accumulating schedule, so a 25 Hz stream
    capped at 10 Hz yields 10 Hz on average). Dropped samples give a passive update.
 4. Smoothing (MotionFilter), 5. calibration or tilt estimation + PostureDetector,
 6. ReminderDecisionEngine on the update where a tilt becomes sustained.
"""

from __future__ import annotations

from typing import Optional

from .calibration import CalibrationService
from .detector import PHASE_NEUTRAL, PostureDetector, component_degrees
from .geometry import gravity_in_head_frame, length, normalized
from .model import (
    CALIBRATING,
    NEEDS_CALIBRATION,
    SENSOR_INTERRUPTED,
    UNAVAILABLE,
    CalibrationOutcome,
    MotionSample,
    NeutralBaseline,
    PostureConfiguration,
    PostureEpisode,
    PostureState,
    PostureUpdate,
    TiltEstimate,
)
from .motion_filter import MotionFilter
from .reminder import ReminderDecisionEngine
from .tilt import estimate_tilt

# Decimation schedule tolerance (seconds).
DECIMATION_EPSILON = 1e-6


class PostureMonitor:
    def __init__(
        self,
        configuration: Optional[PostureConfiguration] = None,
        baseline: Optional[NeutralBaseline] = None,
        orthogonalize_axes: bool = True,
    ) -> None:
        self.configuration = configuration if configuration is not None else PostureConfiguration()
        self.baseline = baseline
        self.orthogonalize_axes = orthogonalize_axes
        self.filter = MotionFilter()
        self.calibration = CalibrationService()
        self.detector = PostureDetector()
        self.reminders = ReminderDecisionEngine()
        self.last_received_timestamp: Optional[float] = None
        self.last_processed_timestamp: Optional[float] = None
        self.next_processing_due: Optional[float] = None
        self.has_data = False
        self.last_tilt: Optional[TiltEstimate] = None
        self.pending_episode: Optional[PostureEpisode] = None

    # MARK: - Public API

    @property
    def state(self) -> PostureState:
        if self.calibration.is_active:
            return PostureState(CALIBRATING, progress=self.calibration.progress(self.configuration.calibration_duration))
        if not self.has_data:
            return PostureState(UNAVAILABLE)
        if self.baseline is None:
            return PostureState(NEEDS_CALIBRATION)
        return self.detector.state

    def begin_calibration(self) -> None:
        """Starts collecting a new baseline. An open sustained episode is closed at the last
        processed timestamp and delivered with the next update."""
        if self.detector.phase != PHASE_NEUTRAL:
            end = self.last_processed_timestamp if self.last_processed_timestamp is not None else 0.0
            episode = self.detector.interrupt(end)
            if episode is not None and self.pending_episode is None:
                self.pending_episode = episode
        self.detector.reset()
        self.calibration.begin()

    def cancel_calibration(self) -> None:
        self.calibration.cancel()
        self.detector.reset()

    def reset_cooldown(self) -> None:
        self.reminders.reset()

    def interrupt(self, at: float) -> PostureUpdate:
        episode, outcome = self._interrupt(at)
        return PostureUpdate(
            timestamp=at,
            state=self.state,
            tilt=None,
            completed_episode=episode,
            calibration_outcome=outcome,
        )

    def process(self, sample: MotionSample) -> PostureUpdate:
        t = sample.timestamp
        raw = sample.gravity if sample.gravity is not None else gravity_in_head_frame(sample.attitude)
        gravity = normalized(raw)
        if length(gravity) == 0.0:
            return self._passive_update(t, None, None)
        if self.last_received_timestamp is not None and t <= self.last_received_timestamp:
            return self._passive_update(t, None, None)

        gap_episode = None
        gap_outcome = None
        if self.last_received_timestamp is not None and t - self.last_received_timestamp > self.configuration.max_sample_gap:
            gap_episode, gap_outcome = self._interrupt(self.last_received_timestamp)
        self.last_received_timestamp = t

        if not self._should_process(t):
            return self._passive_update(t, gap_episode, gap_outcome)

        config = self.configuration
        smoothed = self.filter.update(gravity, t, config.smoothing_time_constant)
        self.has_data = True
        self.last_processed_timestamp = t

        episode = self._take_pending_episode()
        if episode is None:
            episode = gap_episode
        outcome = gap_outcome
        reminder = None
        tilt = None

        if self.calibration.is_active:
            step = self.calibration.add(smoothed, t, config)
            if step.finished:
                if step.failure is None:
                    previous_version = self.baseline.version if self.baseline is not None else 0
                    self.baseline = NeutralBaseline(
                        gravity=step.mean_gravity,
                        captured_at=t,
                        sample_count=step.sample_count,
                        version=previous_version + 1,
                    )
                    outcome = CalibrationOutcome(succeeded=True, baseline=self.baseline)
                else:
                    outcome = CalibrationOutcome(succeeded=False, failure=step.failure)
                self.detector.reset()
            if self.baseline is not None:
                tilt = self._estimate(t, smoothed)
        elif self.baseline is not None:
            tilt = self._estimate(t, smoothed)
            out = self.detector.update(tilt, config)
            if out.completed_episode is not None and episode is None:
                episode = out.completed_episode
            if out.became_sustained:
                direction = self.detector.direction
                decision = self.reminders.evaluate(
                    timestamp=t,
                    direction=direction,
                    deviation_degrees=component_degrees(tilt, direction),
                    sustained_seconds=t - self.detector.since,
                    cooldown=config.reminder_cooldown,
                )
                if decision is not None:
                    self.detector.mark_reminder_triggered()
                    reminder = decision

        self.last_tilt = tilt
        return PostureUpdate(
            timestamp=t,
            state=self.state,
            tilt=tilt,
            reminder=reminder,
            completed_episode=episode,
            calibration_outcome=outcome,
        )

    # MARK: - Internals

    def _estimate(self, t: float, smoothed) -> TiltEstimate:
        return estimate_tilt(t, smoothed, self.baseline.gravity, self.configuration.axes, self.orthogonalize_axes)

    def _take_pending_episode(self) -> Optional[PostureEpisode]:
        episode = self.pending_episode
        self.pending_episode = None
        return episode

    def _interrupt(self, at: float):
        episode = self._take_pending_episode()
        detector_episode = self.detector.interrupt(at)
        if episode is None:
            episode = detector_episode
        outcome = None
        if self.calibration.is_active:
            self.calibration.cancel()
            outcome = CalibrationOutcome(succeeded=False, failure=SENSOR_INTERRUPTED)
        self.filter.reset()
        self.has_data = False
        self.last_received_timestamp = None
        self.last_processed_timestamp = None
        self.next_processing_due = None
        self.last_tilt = None
        return episode, outcome

    def _should_process(self, t: float) -> bool:
        rate = self.configuration.max_processing_rate_hz
        if rate is None or rate <= 0.0:
            self.next_processing_due = None
            return True
        period = 1.0 / rate
        if self.next_processing_due is None:
            self.next_processing_due = t + period
            return True
        if t + DECIMATION_EPSILON < self.next_processing_due:
            return False
        self.next_processing_due += period
        if self.next_processing_due <= t:
            self.next_processing_due = t + period
        return True

    def _passive_update(self, t: float, episode, outcome) -> PostureUpdate:
        pending = self._take_pending_episode()
        if pending is not None and episode is None:
            episode = pending
        return PostureUpdate(
            timestamp=t,
            state=self.state,
            tilt=self.last_tilt,
            completed_episode=episode,
            calibration_outcome=outcome,
        )
