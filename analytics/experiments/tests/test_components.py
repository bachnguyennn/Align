import math

import pytest

from align_reference.calibration import CalibrationService
from align_reference.detector import PostureDetector, dominant_direction
from align_reference.geometry import Vec3, angle_between_degrees, gravity_in_head_frame
from align_reference.model import (
    BACKWARD,
    DEVIATING,
    FORWARD,
    INSUFFICIENT_SAMPLES,
    LEFT,
    NEUTRAL,
    RIGHT,
    SUSTAINED_TILT,
    TOO_MUCH_MOVEMENT,
    PostureConfiguration,
    TiltEstimate,
)
from align_reference.motion_filter import MotionFilter
from align_reference.pose import pose_attitude
from align_reference.reminder import ReminderDecisionEngine

CFG = PostureConfiguration()


def g_for(forward, lateral=0.0):
    return gravity_in_head_frame(pose_attitude(forward, lateral))


def tilt(t, forward=0.0, lateral=0.0):
    return TiltEstimate(t, forward, lateral, math.hypot(forward, lateral))


# MARK: MotionFilter


def test_filter_first_sample_passes_through_and_step_reaches_63_percent_at_tau():
    f = MotionFilter()
    g0, g1 = g_for(0), g_for(10)
    assert f.update(g0, 0.0, 0.5) == g0
    out = None
    for i in range(1, 501):  # 1 kHz for 0.5 s
        out = f.update(g1, i * 0.001, 0.5)
    angle = angle_between_degrees(g0, out)
    assert angle == pytest.approx(10 * (1 - math.exp(-1)), abs=0.05)


def test_filter_response_is_sample_rate_independent():
    g0, g1 = g_for(0), g_for(10)
    results = []
    for rate in (25.0, 100.0):
        f = MotionFilter()
        f.update(g0, 0.0, 0.5)
        n = int(rate * 1.0)
        out = None
        for i in range(1, n + 1):
            out = f.update(g1, i / rate, 0.5)
        results.append(angle_between_degrees(g0, out))
    assert results[0] == pytest.approx(results[1], abs=0.02)


def test_filter_zero_time_constant_and_reset():
    f = MotionFilter()
    f.update(g_for(0), 0.0, 0.0)
    g1 = g_for(12)
    assert f.update(g1, 0.04, 0.0) == pytest.approx(g1)
    f.reset()
    assert f.value is None


# MARK: CalibrationService


def run_calibration(gravities, rate=25.0, config=CFG):
    c = CalibrationService()
    c.begin()
    step = None
    for i, g in enumerate(gravities):
        step = c.add(g, i / rate, config)
        if step.finished:
            return step, i + 1
    return step, len(gravities)


def test_calibration_succeeds_with_mean_gravity_after_duration():
    gs = [g_for(2 * math.sin(i * 0.3), 1.0) for i in range(400)]
    step, used = run_calibration(gs)
    assert step.finished and step.failure is None
    assert used == 251  # samples at t = 0 .. 10.0 inclusive at 25 Hz
    assert step.sample_count == 251
    assert angle_between_degrees(step.mean_gravity, g_for(0, 1.0)) < 0.2


def test_calibration_reports_progress():
    c = CalibrationService()
    c.begin()
    c.add(g_for(0), 0.0, CFG)
    s = c.add(g_for(0), 5.0, CFG)
    assert not s.finished and s.progress == pytest.approx(0.5)


def test_calibration_fails_with_too_much_movement():
    gs = [g_for(8 * math.sin(i * 0.1)) for i in range(400)]
    step, _ = run_calibration(gs)
    assert step.failure == TOO_MUCH_MOVEMENT


def test_calibration_fails_with_insufficient_samples():
    gs = [g_for(0) for _ in range(100)]
    step, used = run_calibration(gs, rate=5.0)  # 10 s at 5 Hz = 51 samples
    assert step.failure == INSUFFICIENT_SAMPLES and used == 51


# MARK: PostureDetector


def test_detector_neutral_deviating_sustained_and_episode():
    d = PostureDetector()
    assert d.update(tilt(0, 10), CFG).state.kind == NEUTRAL
    out = d.update(tilt(1, 16), CFG)
    assert out.state.kind == DEVIATING and out.state.direction == FORWARD and out.state.since == 1
    out = d.update(tilt(30.9, 16), CFG)
    assert out.state.kind == DEVIATING
    out = d.update(tilt(31.0, 20), CFG)
    assert out.state.kind == SUSTAINED_TILT and out.became_sustained
    assert not d.update(tilt(32, 13), CFG).became_sustained  # hysteresis: 13 >= 15 - 3
    out = d.update(tilt(40, 11.9), CFG)
    assert out.state.kind == NEUTRAL
    ep = out.completed_episode
    assert ep.direction == FORWARD and ep.start_timestamp == 1 and ep.end_timestamp == 40
    assert ep.peak_deviation_degrees == 20 and not ep.reminder_triggered


def test_short_deviation_produces_no_episode():
    d = PostureDetector()
    d.update(tilt(0, 20), CFG)
    out = d.update(tilt(5, 0), CFG)
    assert out.state.kind == NEUTRAL and out.completed_episode is None


@pytest.mark.parametrize("forward,lateral,expected", [
    (16, 0, FORWARD), (-21, 0, BACKWARD), (0, 15, RIGHT), (0, -15.5, LEFT),
    (-21, 16, RIGHT),   # backward 21/20 = 1.05 < right 16/15 = 1.067
    (18, -16, FORWARD),  # 1.2 vs 1.067
    (-19, 0, None), (14.9, 14.9, None),
])
def test_direction_precedence_by_ratio(forward, lateral, expected):
    assert dominant_direction(tilt(0, forward, lateral), CFG) == expected


def test_direction_is_locked_during_deviation_and_release_can_start_new_direction():
    d = PostureDetector()
    d.update(tilt(0, 16, 0), CFG)
    out = d.update(tilt(1, 16, 30), CFG)  # lateral now dominates, but forward stays engaged
    assert out.state.direction == FORWARD
    out = d.update(tilt(2, 5, 30), CFG)  # forward released; right over threshold
    assert out.state.kind == DEVIATING and out.state.direction == RIGHT and out.state.since == 2


def test_interrupt_closes_only_sustained():
    d = PostureDetector()
    d.update(tilt(0, 20), CFG)
    assert d.interrupt(3) is None
    d.update(tilt(10, 20), CFG)
    d.update(tilt(40, 20), CFG)
    ep = d.interrupt(41)
    assert ep.end_timestamp == 41 and ep.start_timestamp == 10
    assert d.state.kind == NEUTRAL


def test_floating_point_duration_edge_counts_as_elapsed():
    d = PostureDetector()
    d.update(tilt(15.04, 20), CFG)
    out = d.update(tilt(45.04, 20), CFG)  # 45.04 - 15.04 = 29.999999999999996
    assert out.became_sustained


# MARK: ReminderDecisionEngine


def test_reminder_cooldown_and_reset():
    r = ReminderDecisionEngine()
    assert r.evaluate(100, FORWARD, 20, 30, 300) is not None
    assert r.evaluate(399.9, FORWARD, 20, 30, 300) is None
    assert r.evaluate(400, FORWARD, 20, 30, 300) is not None
    assert r.evaluate(401, FORWARD, 20, 30, 300) is None
    r.reset()
    assert r.evaluate(402, FORWARD, 20, 30, 300) is not None


def test_reminder_allowed_when_clock_goes_backwards():
    r = ReminderDecisionEngine()
    r.evaluate(1000, FORWARD, 20, 30, 300)
    assert r.evaluate(10, LEFT, 20, 30, 300) is not None
