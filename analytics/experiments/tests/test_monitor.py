import math

import pytest

from align_reference.geometry import Vec3
from align_reference.model import (
    CALIBRATING,
    DEVIATING,
    FORWARD,
    NEEDS_CALIBRATION,
    NEUTRAL,
    SENSOR_INTERRUPTED,
    SUSTAINED_TILT,
    UNAVAILABLE,
    MotionSample,
    NeutralBaseline,
    PostureConfiguration,
)
from align_reference.monitor import PostureMonitor
from align_reference.pose import pose_sample

RATE = 25.0
DT = 1.0 / RATE


def baseline(version=1):
    return NeutralBaseline(gravity=Vec3(0.0, 0.0, -1.0), captured_at=0.0, sample_count=250, version=version)


def feed(m, start, end, forward=0.0, lateral=0.0, rate=RATE):
    """Feeds samples for start <= t < end; returns the updates."""
    out = []
    i = 0
    while True:
        t = round(start + i / rate, 6)
        if t >= end - 1e-9:
            break
        out.append(m.process(pose_sample(t, forward, lateral)))
        i += 1
    return out


def calibrated_monitor(config=None):
    m = PostureMonitor(config or PostureConfiguration())
    m.begin_calibration()
    feed(m, 0.0, 10.0 + DT)
    assert m.baseline is not None
    return m


def test_initial_states():
    m = PostureMonitor()
    assert m.state.kind == UNAVAILABLE
    u = m.process(pose_sample(0.0))
    assert u.state.kind == NEEDS_CALIBRATION and u.tilt is None
    m2 = PostureMonitor(baseline=baseline())
    assert m2.process(pose_sample(0.0)).state.kind == NEUTRAL


def test_calibration_progress_single_outcome_and_version():
    m = PostureMonitor()
    m.begin_calibration()
    assert m.state.kind == CALIBRATING and m.state.progress == 0.0
    ups = feed(m, 0.0, 12.0)
    outcomes = [u for u in ups if u.calibration_outcome is not None]
    assert len(outcomes) == 1
    assert outcomes[0].timestamp == pytest.approx(10.0)
    assert outcomes[0].calibration_outcome.succeeded
    assert ups[125].state.kind == CALIBRATING and ups[125].state.progress == pytest.approx(0.5)
    assert outcomes[0].state.kind == NEUTRAL
    assert m.baseline.version == 1 and m.baseline.sample_count == 251
    m.begin_calibration()
    feed(m, 12.0, 23.0)
    assert m.baseline.version == 2


def test_version_continues_from_stored_baseline():
    m = PostureMonitor(baseline=baseline(version=5))
    m.begin_calibration()
    feed(m, 0.0, 10.5)
    assert m.baseline.version == 6


def test_sustained_forward_tilt_reminds_once_and_closes_episode():
    m = calibrated_monitor()
    ups = feed(m, 10.04, 20.0)
    ups += feed(m, 20.0, 80.0, forward=25.0)
    ups += feed(m, 80.0, 85.0)
    reminders = [u.reminder for u in ups if u.reminder]
    assert len(reminders) == 1
    r = reminders[0]
    assert r.direction == FORWARD and r.sustained_seconds == pytest.approx(30.0, abs=0.05)
    assert r.deviation_degrees == pytest.approx(25.0, abs=0.1)
    # A 0 -> 25 deg step through the tau = 0.5 s filter crosses 15 deg after tau * ln(25 / 10).
    lag = 0.5 * math.log(25.0 / 10.0)
    assert r.timestamp == pytest.approx(50.0 + lag, abs=DT)
    episodes = [u.completed_episode for u in ups if u.completed_episode]
    assert len(episodes) == 1 and episodes[0].reminder_triggered
    assert episodes[0].end_timestamp == pytest.approx(80.0, abs=0.5)
    assert m.state.kind == NEUTRAL


def test_state_since_is_deviation_onset():
    m = calibrated_monitor()
    feed(m, 10.04, 12.0)
    feed(m, 12.0, 50.0, forward=25.0)
    s = m.state
    assert s.kind == SUSTAINED_TILT and s.since == pytest.approx(12.0 + 0.5 * math.log(2.5), abs=DT)


def test_cooldown_blocks_second_episode_and_reset_cooldown_allows_it():
    m = calibrated_monitor()
    feed(m, 10.04, 12.0)
    first = feed(m, 12.0, 50.0, forward=25.0)
    feed(m, 50.0, 55.0)
    second = feed(m, 55.0, 90.0, forward=25.0)
    assert sum(1 for u in first if u.reminder) == 1
    assert sum(1 for u in second if u.reminder) == 0
    feed(m, 90.0, 95.0)
    m.reset_cooldown()
    third = feed(m, 95.0, 130.0, forward=25.0)
    assert sum(1 for u in third if u.reminder) == 1


def test_tilt_sustained_during_cooldown_reminds_when_cooldown_ends():
    m = calibrated_monitor()
    feed(m, 10.04, 12.0)
    first = feed(m, 12.0, 50.0, forward=25.0)
    feed(m, 50.0, 55.0)
    second = feed(m, 55.0, 400.0, forward=25.0)
    first_time = next(u.reminder.timestamp for u in first if u.reminder)
    deferred = [u.reminder for u in second if u.reminder]
    assert len(deferred) == 1
    assert deferred[0].timestamp == pytest.approx(first_time + 300.0, abs=1.0 / 25.0)


def test_interrupt_closes_episode_and_resets():
    m = calibrated_monitor()
    feed(m, 10.04, 12.0)
    feed(m, 12.0, 45.0, forward=25.0)
    u = m.interrupt(45.5)
    assert u.completed_episode is not None and u.completed_episode.end_timestamp == 45.5
    assert u.state.kind == UNAVAILABLE and u.tilt is None
    # After reconnecting, deviation timers restart.
    u = m.process(pose_sample(50.0, 25.0))
    assert u.state.kind == DEVIATING and u.state.since == 50.0


def test_interrupt_fails_calibration():
    m = PostureMonitor()
    m.begin_calibration()
    feed(m, 0.0, 5.0)
    u = m.interrupt(5.0)
    assert u.calibration_outcome.failure == SENSOR_INTERRUPTED
    assert m.state.kind == UNAVAILABLE
    assert m.process(pose_sample(6.0)).state.kind == NEEDS_CALIBRATION


def test_gap_acts_like_interrupt_at_previous_timestamp():
    m = calibrated_monitor()
    feed(m, 10.04, 12.0)
    feed(m, 12.0, 45.0, forward=25.0)
    last = 45.0 - DT
    u = m.process(pose_sample(47.0, 25.0))
    assert u.completed_episode is not None
    assert u.completed_episode.end_timestamp == pytest.approx(last)
    assert u.state.kind == DEVIATING and u.state.since == 47.0


def test_gap_during_calibration_reports_sensor_interrupted_on_next_sample():
    m = PostureMonitor()
    m.begin_calibration()
    feed(m, 0.0, 4.0)
    u = m.process(pose_sample(6.0))
    assert u.calibration_outcome is not None and u.calibration_outcome.failure == SENSOR_INTERRUPTED
    assert u.state.kind == NEEDS_CALIBRATION


def test_decimation_caps_processing_rate():
    cfg = PostureConfiguration(max_processing_rate_hz=10.0)
    m = PostureMonitor(cfg, baseline=baseline())
    processed = 0
    for i in range(250):  # 10 s at 25 Hz
        before = m.last_processed_timestamp
        m.process(pose_sample(round(i * DT, 6)))
        if m.last_processed_timestamp != before:
            processed += 1
    assert processed == pytest.approx(100, abs=1)


def test_configuration_change_applies_from_next_sample():
    m = calibrated_monitor()
    feed(m, 10.04, 12.0)
    feed(m, 12.0, 14.0, forward=12.0)
    assert m.state.kind == NEUTRAL
    m.configuration = m.configuration.replacing(forward_threshold_degrees=10.0)
    u = m.process(pose_sample(14.0, 12.0))
    assert u.state.kind == DEVIATING


def test_missing_gravity_is_derived_from_attitude():
    m = PostureMonitor(baseline=baseline())
    m.process(pose_sample(0.0, 0.0))
    u = None
    for i in range(1, 100):
        u = m.process(pose_sample(i * DT, 20.0, include_gravity=False))
    assert u.tilt.forward_degrees == pytest.approx(20.0, abs=0.01)


def test_non_increasing_and_zero_gravity_samples_are_ignored():
    m = PostureMonitor(baseline=baseline())
    m.process(pose_sample(1.0))
    before = m.last_processed_timestamp
    m.process(pose_sample(1.0, 30.0))
    m.process(pose_sample(0.5, 30.0))
    m.process(MotionSample(timestamp=2.0, attitude=pose_sample(0).attitude, gravity=Vec3(0, 0, 0)))
    assert m.last_processed_timestamp == before


def test_begin_calibration_during_sustained_tilt_delivers_episode_on_next_update():
    m = calibrated_monitor()
    feed(m, 10.04, 12.0)
    feed(m, 12.0, 45.0, forward=25.0)
    last = m.last_processed_timestamp
    m.begin_calibration()
    assert m.state.kind == CALIBRATING
    u = m.process(pose_sample(45.0, 0.0))
    assert u.completed_episode is not None and u.completed_episode.end_timestamp == last


def test_cancel_calibration_keeps_previous_baseline():
    m = calibrated_monitor()
    b = m.baseline
    m.begin_calibration()
    feed(m, 10.04, 13.0)
    m.cancel_calibration()
    u = m.process(pose_sample(13.0))
    assert m.baseline == b and u.state.kind == NEUTRAL and u.calibration_outcome is None
