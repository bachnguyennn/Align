"""Loading, replaying and checking motion fixtures (format: shared/fixtures/README.md).

The replay loop here is mirrored by the Swift `FixtureReplayTests`.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional

from .geometry import Quat, Vec3
from .model import (
    MotionSample,
    NeutralBaseline,
    PostureConfiguration,
    PostureEpisode,
    PostureUpdate,
    ReminderDecision,
)
from .monitor import PostureMonitor

REPO_ROOT = Path(__file__).resolve().parents[3]
FIXTURE_DIR = REPO_ROOT / "shared" / "fixtures" / "motion"
SCHEMA_VERSION = 1


def load_fixture(path: Path) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def fixture_paths() -> List[Path]:
    return sorted(FIXTURE_DIR.glob("*.json"))


def fixture_samples(fx: dict) -> List[MotionSample]:
    samples = []
    for s in fx["samples"]:
        q = s["q"]
        g = s.get("g")
        r = s.get("r")
        samples.append(
            MotionSample(
                timestamp=float(s["t"]),
                attitude=Quat(float(q[0]), float(q[1]), float(q[2]), float(q[3])),
                gravity=Vec3(float(g[0]), float(g[1]), float(g[2])) if g is not None else None,
                rotation_rate=Vec3(float(r[0]), float(r[1]), float(r[2])) if r is not None else None,
            )
        )
    return samples


def fixture_baseline(fx: dict) -> Optional[NeutralBaseline]:
    b = fx.get("baseline")
    if not b:
        return None
    g = b["gravity"]
    return NeutralBaseline(
        gravity=Vec3(float(g[0]), float(g[1]), float(g[2])),
        captured_at=0.0,
        sample_count=int(b.get("sampleCount", 0)),
        version=int(b.get("version", 1)),
    )


@dataclass
class ReplayResult:
    reminders: List[ReminderDecision] = field(default_factory=list)
    episodes: List[PostureEpisode] = field(default_factory=list)
    calibration_outcomes: List[str] = field(default_factory=list)
    final_state: str = ""
    state_transitions: int = 0
    updates: List[PostureUpdate] = field(default_factory=list)


def replay(
    fx: dict,
    configuration: Optional[PostureConfiguration] = None,
    keep_updates: bool = False,
    orthogonalize_axes: bool = True,
    samples: Optional[List[MotionSample]] = None,
) -> ReplayResult:
    """Replays a fixture. Each action is applied before the first sample whose t >= action t;
    actions after the last sample are applied at the end."""
    config = configuration if configuration is not None else PostureConfiguration.from_overrides(fx.get("config"))
    monitor = PostureMonitor(config, fixture_baseline(fx), orthogonalize_axes=orthogonalize_axes)
    if samples is None:
        samples = fixture_samples(fx)
    actions = sorted(fx.get("actions", []), key=lambda a: float(a["t"]))
    result = ReplayResult()
    previous_kind = [None]

    def record(update: PostureUpdate) -> None:
        if keep_updates:
            result.updates.append(update)
        if update.reminder is not None:
            result.reminders.append(update.reminder)
        if update.completed_episode is not None:
            result.episodes.append(update.completed_episode)
        if update.calibration_outcome is not None:
            result.calibration_outcomes.append(update.calibration_outcome.name)
        kind = update.state.kind
        if previous_kind[0] is not None and kind != previous_kind[0]:
            result.state_transitions += 1
        previous_kind[0] = kind

    def apply(action: dict) -> None:
        kind = action["type"]
        if kind == "beginCalibration":
            monitor.begin_calibration()
        elif kind == "cancelCalibration":
            monitor.cancel_calibration()
        elif kind == "resetCooldown":
            monitor.reset_cooldown()
        elif kind == "interrupt":
            record(monitor.interrupt(float(action["t"])))
        else:
            raise ValueError(f"unknown action type: {kind}")

    ai = 0
    for sample in samples:
        while ai < len(actions) and float(actions[ai]["t"]) <= sample.timestamp:
            apply(actions[ai])
            ai += 1
        record(monitor.process(sample))
    while ai < len(actions):
        apply(actions[ai])
        ai += 1
    result.final_state = monitor.state.kind
    return result


def check_expected(fx: dict, result: ReplayResult) -> List[str]:
    """Returns a list of mismatches between a replay and the fixture's `expected` block."""
    exp = fx["expected"]
    tol = float(exp.get("tolerances", {}).get("timeSeconds", 2.0))
    errors: List[str] = []
    if "calibrationOutcomes" in exp and result.calibration_outcomes != exp["calibrationOutcomes"]:
        errors.append(f"calibrationOutcomes {result.calibration_outcomes} != {exp['calibrationOutcomes']}")
    if len(result.reminders) != len(exp["reminders"]):
        errors.append(f"reminder count {len(result.reminders)} != {len(exp['reminders'])}: "
                      f"{[(round(r.timestamp, 2), r.direction) for r in result.reminders]}")
    else:
        for got, want in zip(result.reminders, exp["reminders"]):
            if got.direction != want["direction"]:
                errors.append(f"reminder direction {got.direction} != {want['direction']}")
            if abs(got.timestamp - float(want["t"])) > tol:
                errors.append(f"reminder t {got.timestamp:.3f} not within {tol} of {want['t']}")
    if len(result.episodes) != len(exp["episodes"]):
        errors.append(f"episode count {len(result.episodes)} != {len(exp['episodes'])}")
    else:
        for got, want in zip(result.episodes, exp["episodes"]):
            if got.direction != want["direction"]:
                errors.append(f"episode direction {got.direction} != {want['direction']}")
            if abs(got.start_timestamp - float(want["start"])) > tol:
                errors.append(f"episode start {got.start_timestamp:.3f} not within {tol} of {want['start']}")
            if abs(got.end_timestamp - float(want["end"])) > tol:
                errors.append(f"episode end {got.end_timestamp:.3f} not within {tol} of {want['end']}")
            if got.reminder_triggered != bool(want["reminderTriggered"]):
                errors.append(f"episode reminderTriggered {got.reminder_triggered} != {want['reminderTriggered']}")
    if "finalState" in exp and result.final_state != exp["finalState"]:
        errors.append(f"finalState {result.final_state} != {exp['finalState']}")
    return errors


def reference_block(result: ReplayResult) -> dict:
    """Exact output of this reference implementation, stored in fixtures for Swift parity."""
    from . import __version__

    return {
        "producedBy": f"align_reference {__version__}",
        "calibrationOutcomes": list(result.calibration_outcomes),
        "reminders": [
            {
                "t": r.timestamp,
                "direction": r.direction,
                "deviationDegrees": round(r.deviation_degrees, 4),
                "sustainedSeconds": round(r.sustained_seconds, 4),
            }
            for r in result.reminders
        ],
        "episodes": [
            {
                "direction": e.direction,
                "start": e.start_timestamp,
                "end": e.end_timestamp,
                "peakDeviationDegrees": round(e.peak_deviation_degrees, 4),
                "reminderTriggered": e.reminder_triggered,
            }
            for e in result.episodes
        ],
        "finalState": result.final_state,
        "stateTransitions": result.state_transitions,
    }
