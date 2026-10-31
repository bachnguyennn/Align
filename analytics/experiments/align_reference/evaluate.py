"""Evaluation of the reference posture pipeline on synthetic data (A-04).

Run from analytics/experiments:
    ../.venv/Scripts/python -m align_reference.evaluate            # Windows
    ../.venv/bin/python -m align_reference.evaluate                # macOS/Linux
Options: --seeds N (default 20), --out PATH (default results/evaluation.md).

Every number is produced by replaying freshly synthesized scenarios (generator.py motion model)
through align_reference.monitor.PostureMonitor. Synthetic data cannot validate real-world
accuracy; it measures the algorithm's timing behaviour and robustness to the modelled noise.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
import time
from pathlib import Path
from typing import Callable, Dict, List, Optional, Sequence

import numpy as np

from .fixtures import replay
from .generator import (
    AXES_CONFIG,
    CALIBRATE_AT_START,
    Glance,
    ScenarioSpec,
    brief_glances_down,
    gradual_forward_slouch,
    looking_up_backward,
    lateral_right_tilt,
    steady_neutral,
    synthesize,
    truth_episode,
)
from .geometry import gravity_in_head_frame
from .model import BACKWARD, DEVIATING, FORWARD, RIGHT, PostureConfiguration
from .pose import pose_attitude
from .tilt import estimate_tilt

RESULTS_DIR = Path(__file__).resolve().parents[1] / "results"


# MARK: - Helpers


def build(spec: ScenarioSpec) -> dict:
    fixture, _ = synthesize(spec)
    return fixture


def config_for(spec: ScenarioSpec, **changes) -> PostureConfiguration:
    return PostureConfiguration.from_overrides(spec.config).replacing(**changes)


def deviating_entries(result) -> int:
    count = 0
    previous = None
    for u in result.updates:
        if u.state.kind == DEVIATING and previous != DEVIATING:
            count += 1
        previous = u.state.kind
    return count


def fmt(x: Optional[float], digits: int = 2) -> str:
    if x is None or (isinstance(x, float) and math.isnan(x)):
        return "n/a"
    return f"{x:.{digits}f}"


def table(headers: Sequence[str], rows: List[Sequence]) -> str:
    out = ["| " + " | ".join(headers) + " |", "|" + "|".join("---" for _ in headers) + "|"]
    for r in rows:
        out.append("| " + " | ".join(str(c) for c in r) + " |")
    return "\n".join(out)


def stats(values: List[float]) -> str:
    if not values:
        return "n/a"
    a = np.array(values)
    return f"{a.mean():.2f} (min {a.min():.2f}, max {a.max():.2f})"


def hold_spec(seed: int, forward: float = 0.0, lateral: float = 0.0, hold: float = 60.0, **kw) -> ScenarioSpec:
    """Calibrate, neutral to 12 s, 3 s ramp to the pose, hold, 3 s ramp back, 7 s neutral."""
    end_hold = 15.0 + hold
    return ScenarioSpec(
        name="hold", description="", seed=seed, duration=end_hold + 10.0, actions=list(CALIBRATE_AT_START),
        keyframes=[(0, 0, 0), (12, 0, 0), (15, forward, lateral), (end_hold, forward, lateral), (end_hold + 3, 0, 0)],
        expected=lambda s: {}, **kw)


def glance_spec(seed: int, duration: float, depth: float = 30.0) -> ScenarioSpec:
    return ScenarioSpec(
        name="glance", description="", seed=seed, duration=20.0 + duration + 10.0, actions=list(CALIBRATE_AT_START),
        glances=[Glance(start=15.0, duration=duration, forward=depth, ramp=0.4)], expected=lambda s: {})


# MARK: - Experiments


def latency(seeds: int) -> str:
    rows = []
    cases = [
        ("gradual_forward_slouch", gradual_forward_slouch, FORWARD, 20.0),
        ("lateral_right_tilt", lateral_right_tilt, RIGHT, 15.0),
        ("looking_up_backward", looking_up_backward, BACKWARD, 15.0),
    ]
    for name, builder, direction, onset_rel in cases:
        from_cross, from_onset, extra = [], [], []
        detected = 0
        for k in range(seeds):
            spec = builder(seed=1000 + k)
            fx = build(spec)
            res = replay(fx)
            cfg = config_for(spec)
            cross_rel, _ = truth_episode(spec, direction, 11.0)
            cross = spec.start_timestamp + cross_rel
            onset = spec.start_timestamp + onset_rel
            r = [x for x in res.reminders if x.direction == direction]
            if len(res.reminders) == 1 and r:
                detected += 1
                from_cross.append(r[0].timestamp - cross)
                from_onset.append(r[0].timestamp - onset)
                extra.append(r[0].timestamp - cross - cfg.sustained_duration)
        rows.append([name, f"{detected}/{seeds}", stats(from_onset), stats(from_cross), stats(extra)])
    return table(["scenario", "exactly 1 reminder", "reminder − tilt onset (s)", "reminder − truth threshold crossing (s)",
                  "delay beyond sustainedDuration (s)"], rows)


def false_positives(seeds: int) -> str:
    rows = []
    for name, builder in (("steady_neutral", steady_neutral), ("brief_glances_down", brief_glances_down)):
        reminders = episodes = 0
        entries, minutes, transitions = [], 0.0, []
        for k in range(seeds):
            spec = builder(seed=2000 + k)
            res = replay(build(spec), keep_updates=True)
            reminders += len(res.reminders)
            episodes += len(res.episodes)
            mins = (spec.duration - 10.0) / 60.0
            minutes += mins
            entries.append(deviating_entries(res) / mins)
            transitions.append(res.state_transitions)
        rows.append([name, seeds, f"{minutes:.1f}", reminders, episodes, stats(entries)])
    return table(["scenario", "runs", "monitored minutes", "reminders", "episodes", "entries into `deviating` per minute"], rows)


def glance_duration_sweep(seeds: int) -> str:
    rows = []
    for duration in (5.0, 10.0, 20.0, 29.0, 31.0, 32.0, 40.0):
        reminded = 0
        for k in range(seeds):
            res = replay(build(glance_spec(3000 + k, duration)))
            reminded += 1 if res.reminders else 0
        rows.append([f"{duration:.0f}", f"{reminded}/{seeds}"])
    return table(["30° glance length incl. 0.4 s ramps (s)", "runs with a reminder"], rows)


def hover_sweep(seeds: int) -> str:
    """Head held near the forward threshold: flicker vs hysteresis and smoothing."""
    rows = []
    for hysteresis in (0.0, 1.0, 3.0, 5.0):
        for tau in (0.0, 0.5, 2.0):
            for offset in (-1.0, 0.0, 1.0):
                entries, eps = [], []
                for k in range(seeds):
                    spec = hold_spec(4000 + k, forward=15.0 + offset, hold=60.0)
                    cfg = config_for(spec, hysteresis_degrees=hysteresis, smoothing_time_constant=tau)
                    res = replay(build(spec), configuration=cfg, keep_updates=True)
                    entries.append(deviating_entries(res))
                    eps.append(len(res.episodes))
                rows.append([fmt(hysteresis, 0), fmt(tau, 1), f"{15 + offset:+.0f}".lstrip("+"),
                             fmt(float(np.mean(entries)), 1), int(np.max(entries)), fmt(float(np.mean(eps)), 2)])
    return table(["hysteresis (°)", "tau (s)", "held angle (°, threshold 15)", "mean entries into deviating / 60 s hold",
                  "max entries", "mean sustained episodes"], rows)


def threshold_sweep(seeds: int) -> str:
    rows = []
    angles = (12.0, 15.0, 18.0, 20.0, 25.0)
    for threshold in (10.0, 12.0, 15.0, 18.0, 20.0):
        detect = []
        for angle in angles:
            hits = 0
            for k in range(seeds):
                spec = hold_spec(5000 + k, forward=angle, hold=45.0)
                res = replay(build(spec), configuration=config_for(spec, forward_threshold_degrees=threshold))
                hits += 1 if res.reminders else 0
            detect.append(f"{hits}/{seeds}")
        fp = 0
        for k in range(seeds):
            spec = steady_neutral(seed=6000 + k, sway_deg=1.0, micro_interval=4.0)
            res = replay(build(spec), configuration=config_for(spec, forward_threshold_degrees=threshold))
            fp += len(res.reminders)
        rows.append([fmt(threshold, 0)] + detect + [fp])
    return table(["forward threshold (°)"] + [f"45 s hold at {a:.0f}°" for a in angles] +
                 ["reminders on noisy neutral (sway 1°, micro every 4 s)"], rows)


def tau_sweep(seeds: int) -> str:
    rows = []
    for tau in (0.0, 0.25, 0.5, 1.0, 2.0):
        lat = []
        for k in range(seeds):
            spec = gradual_forward_slouch(seed=7000 + k)
            res = replay(build(spec), configuration=config_for(spec, smoothing_time_constant=tau))
            cross_rel, _ = truth_episode(spec, FORWARD, 11.0)
            if len(res.reminders) == 1:
                lat.append(res.reminders[0].timestamp - cross_rel - 30.0)
        glance_entries = []
        for k in range(seeds):
            spec = brief_glances_down(seed=7500 + k)
            res = replay(build(spec), configuration=config_for(spec, smoothing_time_constant=tau), keep_updates=True)
            glance_entries.append(deviating_entries(res))
        rows.append([fmt(tau, 2), f"{len(lat)}/{seeds}", stats(lat), fmt(float(np.mean(glance_entries)), 1)])
    return table(["tau (s)", "slouch detected", "delay beyond crossing + 30 s (s)", "mean deviating entries, glance scenario"], rows)


def calibration_noise(seeds: int) -> str:
    rows = []
    for sway in (0.5, 1.0, 1.5, 2.0, 3.0):
        ok = 0
        for k in range(seeds):
            spec = steady_neutral(seed=8000 + k, sway_deg=sway)
            spec.duration = 12.0
            res = replay(build(spec))
            ok += 1 if res.calibration_outcomes == ["succeeded"] else 0
        rows.append([fmt(sway, 1), f"{ok}/{seeds}"])
    return table(["sway std (°) during calibration", "calibrations succeeded (spread limit 5°)"], rows)


def axis_projection() -> str:
    rows = []
    axes = PostureConfiguration().axes
    for pitch, roll in ((0, 0), (10, 0), (20, 0), (0, 10), (10, -5), (20, 10)):
        g0 = gravity_in_head_frame(pose_attitude(0, 0, 0, pitch, roll))
        errs = {}
        for ortho in (True, False):
            g_f = gravity_in_head_frame(pose_attitude(20, 0, 0, pitch, roll))
            g_l = gravity_in_head_frame(pose_attitude(0, 20, 0, pitch, roll))
            tf = estimate_tilt(0, g_f, g0, axes, ortho)
            tl = estimate_tilt(0, g_l, g0, axes, ortho)
            errs[ortho] = (tf.forward_degrees - 20, tl.lateral_degrees - 20, tf.lateral_degrees, tl.forward_degrees)
        rows.append([f"{pitch}/{roll}"] + [fmt(v, 3) for v in errs[True]] + [fmt(v, 3) for v in errs[False]])
    return table(["mount pitch/roll (°)", "baseline-plane: fwd err", "lat err", "fwd→lat crosstalk", "lat→fwd crosstalk",
                  "plain: fwd err", "lat err", "fwd→lat crosstalk", "lat→fwd crosstalk"], rows)


def decimation(seeds: int) -> str:
    rows = []
    for rate in (None, 15.0, 10.0, 5.0):
        lat, ok_cal = [], 0
        for k in range(seeds):
            spec = gradual_forward_slouch(seed=9000 + k)
            res = replay(build(spec), configuration=config_for(spec, max_processing_rate_hz=rate,
                                                               minimum_calibration_samples=40))
            ok_cal += 1 if res.calibration_outcomes == ["succeeded"] else 0
            cross_rel, _ = truth_episode(spec, FORWARD, 11.0)
            if len(res.reminders) == 1:
                lat.append(res.reminders[0].timestamp - cross_rel - 30.0)
        rows.append(["none (25 Hz)" if rate is None else f"{rate:.0f} Hz", f"{ok_cal}/{seeds}", f"{len(lat)}/{seeds}", stats(lat)])
    return table(["maxProcessingRateHz", "calibration ok (min samples 40)", "slouch detected", "delay beyond crossing + 30 s (s)"], rows)


def throughput() -> str:
    spec = gradual_forward_slouch(seed=1)
    fx = build(spec)
    n = len(fx["samples"])
    start = time.perf_counter()
    replay(fx)
    elapsed = time.perf_counter() - start
    return f"Python reference: {n} samples in {elapsed * 1000:.0f} ms ({elapsed / n * 1e6:.1f} µs/sample, CPython, informational only)."


# MARK: - Main


def main(argv: List[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seeds", type=int, default=20)
    parser.add_argument("--out", type=Path, default=RESULTS_DIR / "evaluation.md")
    args = parser.parse_args(argv)
    seeds = args.seeds
    t0 = time.perf_counter()
    sections = [
        ("Detection latency (default configuration)", latency(seeds)),
        ("False positives and flicker on non-slouch scenarios", false_positives(seeds)),
        ("Glance length vs reminder (sustainedDuration 30 s)", glance_duration_sweep(seeds)),
        ("Flicker near threshold: hysteresis x smoothing", hover_sweep(max(5, seeds // 2))),
        ("Threshold sensitivity", threshold_sweep(max(5, seeds // 2))),
        ("Smoothing time constant sensitivity", tau_sweep(seeds)),
        ("Calibration robustness to sway", calibration_noise(seeds)),
        ("Axis projection with earbud mounting offset (noise-free, 20° poses)", axis_projection()),
        ("Decimation", decimation(max(5, seeds // 2))),
        ("Throughput", throughput()),
    ]
    import numpy

    header = (f"# Align reference evaluation output\n\nGenerated by `python -m align_reference.evaluate --seeds {seeds}` "
              f"(numpy {numpy.__version__}, Python {sys.version.split()[0]}). Seeds per cell: {seeds} unless noted "
              f"(sweeps marked with a hold/hover use {max(5, seeds // 2)}).\n")
    body = "\n\n".join(f"## {title}\n\n{content}" for title, content in sections)
    text = header + "\n" + body + f"\n\nTotal runtime: {time.perf_counter() - t0:.0f} s.\n"
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(text, encoding="utf-8", newline="\n")
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
