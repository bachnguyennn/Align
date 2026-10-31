"""Synthetic AirPods head-motion fixture generator.

Model (all angles in degrees):
- True head pose = keyframes (cosine-eased) + glances (raised-cosine trapezoids): forward
  flexion (+ = chin to chest) and lateral bend (+ = right ear to right shoulder).
- Natural sway: Ornstein-Uhlenbeck process per axis (std `sway_deg`, time constant 1.5 s) plus a
  0.25 Hz breathing component on the forward axis.
- Micro-movements: Poisson (mean every `micro_interval` s) raised-cosine bumps of N(0, 1.5 deg)
  (clipped to +-4 deg), 0.6-2 s long, suppressed during calibration windows (the user is asked
  to hold still).
- Heading: slow random walk plus occasional head turns of 15-45 deg (heading must not matter).
- Earbud mounting offset (`mount_pitch`, `mount_roll`) between head frame and device frame.
- Sensor noise: white rotation noise of `sensor_noise_deg` per axis on the gravity vector.

Frames: world is Z-up (Core Motion xArbitraryZVertical), gravity (0, 0, -1) g. Head frame (D-011,
unverified on hardware): +X right ear, +Y nose, +Z up at neutral. Axes are never hard-coded: they
come from the fixture's configuration (`forwardAxis`/`lateralAxis`, written explicitly into every
fixture and equal to the AlignCore default (-1,0,0)/(0,1,0)). Device attitude
q = Yaw(heading) * Tilt(forward*forwardAxis + lateral*lateralAxis) * Mount (pitch about
forwardAxis, roll about lateralAxis); gravity in the device frame = q* (0,0,-1) q
(see `pose.py`).

Run `python -m align_reference.generator` (from analytics/experiments) to rewrite
shared/fixtures/motion/*.json. Output is deterministic for a given numpy version and seed.
"""

from __future__ import annotations

import json
import math
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Dict, List, Optional, Tuple

import numpy as np

from . import __version__
from .fixtures import FIXTURE_DIR, SCHEMA_VERSION, reference_block, replay
from .geometry import (
    Quat,
    Vec3,
    gravity_in_head_frame,
    normalized,
    quat_from_rotation_vector,
    quat_rotate,
)
from .model import BACKWARD, FORWARD, LEFT, RIGHT, HeadAxisConvention, PostureConfiguration
from .pose import pose_attitude

DEFAULT_AXES = HeadAxisConvention()
AXES_CONFIG = {"forwardAxis": list(DEFAULT_AXES.forward_axis), "lateralAxis": list(DEFAULT_AXES.lateral_axis)}

RAD = math.pi / 180.0
GENERATOR_SCRIPT = "analytics/experiments/align_reference/generator.py"


@dataclass
class Glance:
    start: float
    duration: float  # total, including ramps
    forward: float = 0.0
    lateral: float = 0.0
    ramp: float = 0.4


@dataclass
class ScenarioSpec:
    name: str
    description: str
    seed: int
    duration: float
    sample_rate_hz: float = 25.0
    start_timestamp: float = 0.0
    config: Dict = field(default_factory=lambda: dict(AXES_CONFIG))
    actions: List[Dict] = field(default_factory=list)
    keyframes: List[Tuple[float, float, float]] = field(default_factory=lambda: [(0.0, 0.0, 0.0)])
    glances: List[Glance] = field(default_factory=list)
    gaps: List[Tuple[float, float]] = field(default_factory=list)  # no samples with start <= t < end
    calm_windows: List[Tuple[float, float]] = field(default_factory=lambda: [(0.0, 11.0)])
    wobble: Optional[Callable[[float], Tuple[float, float]]] = None  # extra (forward, lateral)
    sway_deg: float = 0.5
    micro_interval: float = 8.0
    sensor_noise_deg: float = 0.05
    head_turn_interval: float = 15.0
    mount_pitch: float = 8.0
    mount_roll: float = -3.0
    timestamp_jitter: float = 0.004  # std of delivery-time jitter, seconds
    expected: Callable[["ScenarioSpec"], Dict] = None  # type: ignore[assignment]

    # Relative-time helpers (seconds since the fixture's start).
    def abs_t(self, rel: float) -> float:
        return round(self.start_timestamp + rel, 4)


# MARK: - Truth profile


def _ease(u: float) -> float:
    return (1.0 - math.cos(math.pi * u)) / 2.0


def keyframe_pose(keyframes: List[Tuple[float, float, float]], t: float) -> Tuple[float, float]:
    if t <= keyframes[0][0]:
        return keyframes[0][1], keyframes[0][2]
    for (t0, f0, l0), (t1, f1, l1) in zip(keyframes, keyframes[1:]):
        if t0 <= t < t1:
            s = _ease((t - t0) / (t1 - t0))
            return f0 + (f1 - f0) * s, l0 + (l1 - l0) * s
    return keyframes[-1][1], keyframes[-1][2]


def glance_envelope(g: Glance, t: float) -> float:
    if t < g.start or t > g.start + g.duration:
        return 0.0
    x = t - g.start
    if x < g.ramp:
        return _ease(x / g.ramp)
    if x > g.duration - g.ramp:
        return _ease((g.duration - x) / g.ramp)
    return 1.0


def truth_pose(spec: ScenarioSpec, t: float) -> Tuple[float, float]:
    """Noise-free intended pose (forward, lateral) at relative time t."""
    f, l = keyframe_pose(spec.keyframes, t)
    for g in spec.glances:
        e = glance_envelope(g, t)
        f += g.forward * e
        l += g.lateral * e
    if spec.wobble is not None:
        wf, wl = spec.wobble(t)
        f += wf
        l += wl
    return f, l


def first_time(spec: ScenarioSpec, predicate: Callable[[float, float], bool], after: float, step: float = 0.001) -> float:
    """First relative time >= `after` where predicate(forward, lateral) holds on the truth."""
    t = after
    while t <= spec.duration:
        f, l = truth_pose(spec, t)
        if predicate(f, l):
            return t
        t += step
    raise ValueError(f"{spec.name}: predicate never true after {after}")


# MARK: - Synthesis


def _ou(rng: np.random.Generator, n: int, dt: float, std: float, tau: float) -> np.ndarray:
    a = math.exp(-dt / tau)
    b = std * math.sqrt(1.0 - a * a)
    out = np.empty(n)
    x = rng.normal(0.0, std)
    for i in range(n):
        x = a * x + b * rng.normal()
        out[i] = x
    return out


def _bumps(rng: np.random.Generator, times: np.ndarray, interval: float, amp_std: float, clip: float,
           dur_range: Tuple[float, float], calm: List[Tuple[float, float]]) -> np.ndarray:
    out = np.zeros_like(times)
    if interval <= 0:
        return out
    t = float(rng.exponential(interval))
    end = float(times[-1]) if len(times) else 0.0
    while t < end:
        d = float(rng.uniform(*dur_range))
        amp = float(np.clip(rng.normal(0.0, amp_std), -clip, clip))
        if not any(a - d <= t <= b for a, b in calm):
            mask = (times >= t) & (times <= t + d)
            u = (times[mask] - t) / d
            out[mask] += amp * np.sin(np.pi * u) ** 2
        t += d + float(rng.exponential(interval))
    return out


def synthesize(spec: ScenarioSpec) -> Tuple[dict, dict]:
    """Returns (fixture dict without `reference`, truth arrays for evaluation)."""
    rng = np.random.default_rng(spec.seed)
    dt = 1.0 / spec.sample_rate_hz
    n_total = int(round(spec.duration * spec.sample_rate_hz)) + 1
    rel_all = np.array([i * dt for i in range(n_total)])
    keep = np.ones(n_total, dtype=bool)
    for a, b in spec.gaps:
        keep &= ~((rel_all >= a - 1e-9) & (rel_all < b - 1e-9))

    sway_f = _ou(rng, n_total, dt, spec.sway_deg, 1.5) + 0.3 * spec.sway_deg * np.sin(2 * np.pi * 0.25 * rel_all + rng.uniform(0, 2 * np.pi))
    sway_l = _ou(rng, n_total, dt, spec.sway_deg * 0.8, 1.5)
    micro_f = _bumps(rng, rel_all, spec.micro_interval, 1.5, 4.0, (0.6, 2.0), spec.calm_windows)
    micro_l = _bumps(rng, rel_all, spec.micro_interval * 1.5, 1.2, 3.0, (0.6, 2.0), spec.calm_windows)
    heading = np.cumsum(rng.normal(0.0, 0.05, n_total)) + rng.uniform(-180, 180)
    heading += _bumps(rng, rel_all, spec.head_turn_interval, 30.0, 45.0, (1.0, 3.0), [])
    noise = rng.normal(0.0, spec.sensor_noise_deg * RAD, (n_total, 3))

    # Delivery jitter: real AirPods deliver ~25 Hz with jitter; the pipeline must use timestamps.
    jitter = np.clip(rng.normal(0.0, spec.timestamp_jitter, n_total), -0.3 * dt, 0.3 * dt)
    axes = PostureConfiguration.from_overrides(spec.config).axes

    samples = []
    truth_t, truth_f, truth_l = [], [], []
    for i in range(n_total):
        if not keep[i]:
            continue
        rel = float(rel_all[i])
        f_true, l_true = truth_pose(spec, rel)
        f = f_true + sway_f[i] + micro_f[i]
        l = l_true + sway_l[i] + micro_l[i]
        q = pose_attitude(f, l, float(heading[i]), spec.mount_pitch, spec.mount_roll, axes)
        g = gravity_in_head_frame(q)
        g = normalized(quat_rotate(quat_from_rotation_vector(Vec3(*noise[i])), g))
        if q.w < 0:
            q = Quat(-q.x, -q.y, -q.z, -q.w)
        t_jittered = rel + float(jitter[i]) if i > 0 else rel
        samples.append({
            "t": round(spec.start_timestamp + t_jittered, 4),
            "q": [round(q.x, 4), round(q.y, 4), round(q.z, 4), round(q.w, 4)],
            "g": [round(g.x, 5), round(g.y, 5), round(g.z, 5)],
        })
        truth_t.append(spec.start_timestamp + rel)
        truth_f.append(f_true)
        truth_l.append(l_true)

    fixture = {
        "schemaVersion": SCHEMA_VERSION,
        "name": spec.name,
        "description": spec.description,
        "generator": {"script": GENERATOR_SCRIPT, "version": __version__, "seed": spec.seed,
                      "numpy": np.__version__},
        "sampleRateHz": spec.sample_rate_hz,
        "startTimestamp": spec.start_timestamp,
        "config": dict(spec.config),
        "baseline": None,
        "actions": [dict(a, t=spec.abs_t(a["t"])) for a in spec.actions],
        "truth": {
            "keyframes": [[spec.abs_t(t), f, l] for t, f, l in spec.keyframes],
            "glances": [{"start": spec.abs_t(g.start), "duration": g.duration, "forward": g.forward,
                         "lateral": g.lateral} for g in spec.glances],
            "gaps": [[spec.abs_t(a), spec.abs_t(b)] for a, b in spec.gaps],
            "mountDegrees": {"pitch": spec.mount_pitch, "roll": spec.mount_roll},
            "swayDegrees": spec.sway_deg,
        },
        "expected": spec.expected(spec),
        "samples": samples,
    }
    truth = {"t": np.array(truth_t), "forward": np.array(truth_f), "lateral": np.array(truth_l)}
    return fixture, truth


# MARK: - Expected-outcome helpers (derived from the noise-free truth, not from the detector)


def _cfg(spec: ScenarioSpec) -> PostureConfiguration:
    return PostureConfiguration.from_overrides(spec.config)


def _component(direction: str, f: float, l: float) -> float:
    return {FORWARD: f, BACKWARD: -f, RIGHT: l, LEFT: -l}[direction]


def _threshold(direction: str, c: PostureConfiguration) -> float:
    return {FORWARD: c.forward_threshold_degrees, BACKWARD: c.backward_threshold_degrees}.get(
        direction, c.lateral_threshold_degrees)


def truth_episode(spec: ScenarioSpec, direction: str, after: float, end_override: Optional[float] = None) -> Tuple[float, float]:
    """(onset, release) relative times on the truth: first reaching threshold after `after`,
    then first falling below threshold - hysteresis."""
    c = _cfg(spec)
    th = _threshold(direction, c)
    onset = first_time(spec, lambda f, l: _component(direction, f, l) >= th, after)
    if end_override is not None:
        return onset, end_override
    release = first_time(spec, lambda f, l: _component(direction, f, l) < th - c.hysteresis_degrees, onset)
    return onset, release


def _expected(spec: ScenarioSpec, calibration: List[str], episodes: List[Dict], final_state: str,
              tolerance: float = 2.0) -> Dict:
    reminders = [{"t": e["reminderAt"], "direction": e["direction"]} for e in episodes if e.get("reminderAt") is not None]
    return {
        "calibrationOutcomes": calibration,
        "reminders": reminders,
        "episodes": [{k: v for k, v in e.items() if k != "reminderAt"} for e in episodes],
        "finalState": final_state,
        "tolerances": {"timeSeconds": tolerance},
    }


def _episode(spec: ScenarioSpec, direction: str, after: float, reminder: bool,
             end_override: Optional[float] = None) -> Dict:
    c = _cfg(spec)
    onset, release = truth_episode(spec, direction, after, end_override)
    return {
        "direction": direction,
        "start": spec.abs_t(round(onset, 2)),
        "end": spec.abs_t(round(release, 2)),
        "reminderTriggered": reminder,
        "reminderAt": spec.abs_t(round(onset + c.sustained_duration, 2)) if reminder else None,
    }


CALIBRATE_AT_START = [{"t": 0.0, "type": "beginCalibration"}]


# MARK: - Scenarios


def steady_neutral(seed: int = 101, **kw) -> ScenarioSpec:
    return ScenarioSpec(
        name="steady_neutral",
        description="Calibrate, then 60 s of neutral posture with natural sway, micro-movements and "
                    "head turns (heading changes). Expect no reminders and no episodes.",
        seed=seed, duration=55.0, actions=list(CALIBRATE_AT_START),
        expected=lambda s: _expected(s, ["succeeded"], [], "neutral"),
        **kw)


def gradual_forward_slouch(seed: int = 102, **kw) -> ScenarioSpec:
    return ScenarioSpec(
        name="gradual_forward_slouch",
        description="Calibrate, neutral until 20 s, drift to 24 deg forward over 10 s, hold 60 s, "
                    "return over 5 s. Expect one forward reminder ~30 s after crossing 15 deg.",
        seed=seed, duration=102.0, actions=list(CALIBRATE_AT_START),
        keyframes=[(0, 0, 0), (20, 0, 0), (30, 24, 0), (90, 24, 0), (95, 0, 0)],
        expected=lambda s: _expected(s, ["succeeded"], [_episode(s, FORWARD, 11, True)], "neutral"),
        **kw)


def brief_glances_down(seed: int = 103, **kw) -> ScenarioSpec:
    rng = np.random.default_rng(seed + 1000)
    glances = []
    t = 15.0
    while t < 64.0:
        d = float(rng.uniform(3.0, 5.0))
        glances.append(Glance(start=round(t, 2), duration=round(d, 2), forward=round(float(rng.uniform(26, 34)), 1)))
        t += d + float(rng.uniform(6.0, 10.0))
    return ScenarioSpec(
        name="brief_glances_down",
        description="Calibrate, then repeated 3-5 s glances down to ~30 deg (e.g. at a phone) "
                    "separated by 6-10 s of neutral. Expect deviations but no reminders/episodes.",
        seed=seed, duration=72.0, sample_rate_hz=20.0, actions=list(CALIBRATE_AT_START), glances=glances,
        expected=lambda s: _expected(s, ["succeeded"], [], "neutral"),
        **kw)


def lateral_right_tilt(seed: int = 104, **kw) -> ScenarioSpec:
    return ScenarioSpec(
        name="lateral_right_tilt",
        description="Starts at t=5000 s (non-zero clock). Calibrate, tilt right ear toward right "
                    "shoulder to 20 deg over 3 s, hold 45 s, return. Expect one 'right' reminder.",
        seed=seed, duration=72.0, start_timestamp=5000.0, actions=list(CALIBRATE_AT_START),
        keyframes=[(0, 0, 0), (15, 0, 0), (18, 0, 20), (63, 0, 20), (66, 0, 0)],
        expected=lambda s: _expected(s, ["succeeded"], [_episode(s, RIGHT, 11, True)], "neutral"),
        **kw)


def cooldown_retrigger(seed: int = 105, **kw) -> ScenarioSpec:
    return ScenarioSpec(
        name="cooldown_retrigger",
        description="sustainedDuration 10 s, reminderCooldown 60 s. Three 22 deg forward tilts: the "
                    "first reminds; the second becomes sustained inside the cooldown (no reminder); "
                    "the third becomes sustained after the cooldown (reminds).",
        seed=seed, duration=116.0, sample_rate_hz=20.0, actions=list(CALIBRATE_AT_START),
        config={**AXES_CONFIG, "sustainedDuration": 10.0, "reminderCooldown": 60.0},
        keyframes=[(0, 0, 0), (14, 0, 0), (16, 22, 0), (34, 22, 0), (36, 0, 0),
                   (40, 0, 0), (42, 22, 0), (58, 22, 0), (60, 0, 0),
                   (88, 0, 0), (90, 22, 0), (106, 22, 0), (108, 0, 0)],
        expected=lambda s: _expected(s, ["succeeded"], [
            _episode(s, FORWARD, 11, True), _episode(s, FORWARD, 37, False), _episode(s, FORWARD, 61, True)],
            "neutral"),
        **kw)


def calibration_too_much_movement(seed: int = 106, **kw) -> ScenarioSpec:
    return ScenarioSpec(
        name="calibration_too_much_movement",
        description="The user nods/looks around (+-9 deg forward, +-4 deg lateral) during the 10 s "
                    "calibration. Expect calibration to fail with tooMuchMovement.",
        seed=seed, duration=15.0, actions=list(CALIBRATE_AT_START),
        wobble=lambda t: ((9.0 * math.sin(2 * math.pi * 0.3 * t), 4.0 * math.sin(2 * math.pi * 0.2 * t))
                          if t <= 10.5 else (0.0, 0.0)),
        expected=lambda s: _expected(s, ["tooMuchMovement"], [], "needsCalibration"),
        **kw)


def disconnect_mid_tilt(seed: int = 107, **kw) -> ScenarioSpec:
    gap = (52.0, 57.0)
    last_before_gap = 52.0 - 1.0 / 25.0
    return ScenarioSpec(
        name="disconnect_mid_tilt",
        description="Calibrate, tilt 22 deg forward from 14 s (reminder ~46 s), then no samples for "
                    "5 s from 52 s (AirPods disconnected). The gap closes the episode at the last "
                    "sample before it; after reconnecting the head returns to neutral at 66-68 s.",
        seed=seed, duration=72.0, actions=list(CALIBRATE_AT_START), gaps=[gap],
        keyframes=[(0, 0, 0), (14, 0, 0), (17, 22, 0), (66, 22, 0), (68, 0, 0)],
        expected=lambda s: _expected(s, ["succeeded"], [
            _episode(s, FORWARD, 11, True, end_override=round(last_before_gap, 4))], "neutral"),
        **kw)


def looking_up_backward(seed: int = 108, **kw) -> ScenarioSpec:
    return ScenarioSpec(
        name="looking_up_backward",
        description="Calibrate, look up 30 deg (e.g. at a high monitor) over 3 s, hold 42 s, return. "
                    "Expect one 'backward' reminder (backward threshold 20 deg).",
        seed=seed, duration=68.0, actions=list(CALIBRATE_AT_START),
        keyframes=[(0, 0, 0), (15, 0, 0), (18, -30, 0), (60, -30, 0), (63, 0, 0)],
        expected=lambda s: _expected(s, ["succeeded"], [_episode(s, BACKWARD, 11, True)], "neutral"),
        **kw)


SCENARIOS: Dict[str, Callable[..., ScenarioSpec]] = {
    "steady_neutral": steady_neutral,
    "gradual_forward_slouch": gradual_forward_slouch,
    "brief_glances_down": brief_glances_down,
    "lateral_right_tilt": lateral_right_tilt,
    "cooldown_retrigger": cooldown_retrigger,
    "calibration_too_much_movement": calibration_too_much_movement,
    "disconnect_mid_tilt": disconnect_mid_tilt,
    "looking_up_backward": looking_up_backward,
}


# MARK: - Writing


def with_reference(fixture: dict) -> dict:
    """Replays the (already rounded) fixture through the reference pipeline and stores the exact
    output as `reference`, placed before `samples`."""
    result = replay(fixture)
    ordered = {k: v for k, v in fixture.items() if k != "samples"}
    ordered["reference"] = reference_block(result)
    ordered["samples"] = fixture["samples"]
    return ordered


def dumps_fixture(fixture: dict) -> str:
    header = {k: v for k, v in fixture.items() if k != "samples"}
    head = json.dumps(header, indent=2)
    assert head.endswith("}")
    rows = ",\n".join(json.dumps(s, separators=(",", ":")) for s in fixture["samples"])
    return head[:-1].rstrip() + ',\n  "samples": [\n' + rows + "\n  ]\n}\n"


def write_all(directory: Path = FIXTURE_DIR) -> List[Path]:
    directory.mkdir(parents=True, exist_ok=True)
    written = []
    for name, build in SCENARIOS.items():
        fixture, _ = synthesize(build())
        # Round-trip through JSON so the reference is computed on exactly what is stored.
        fixture = json.loads(json.dumps(fixture))
        fixture = with_reference(fixture)
        path = directory / f"{name}.json"
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(dumps_fixture(fixture))
        written.append(path)
    return written


def main(argv: List[str]) -> int:
    paths = write_all()
    total = 0
    for p in paths:
        size = p.stat().st_size
        total += size
        print(f"{p.name:40s} {size / 1024:7.1f} KiB")
    print(f"{'total':40s} {total / 1024:7.1f} KiB")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
