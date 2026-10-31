# Motion replay fixtures

`motion/*.json` are synthetic AirPods head-motion recordings with the outcomes the posture
pipeline must produce. The same files are replayed by the Java reference
(`analytics/align-tools`, JUnit) and by Swift (`ios/AlignKit/Tests/PostureDetectionTests`).

They are generated, not hand-edited. **The committed files were produced by the original Python
generator** (`align_reference/generator.py`, numpy 2.5.4; removed after the Java port, D-015, and
still in git history); their `generator` block says so. The Java generator is a port of the same
motion model, so new fixtures come from:

```sh
cd analytics/align-tools
./mvnw -q compile exec:java@generate                                # rewrites shared/fixtures/motion
./mvnw -q compile exec:java@generate -Dexec.args="--out /tmp/fx"    # or write elsewhere
```

(`mvnw.cmd` on Windows without Git Bash; only a JDK 21 is needed.) The Java generator
(`src/main/java/com/bachnguyennn/align/reference/Generator.java`) is seeded and deterministic for
a given seed on every JDK and platform (`SplittableRandom` + Box-Muller + `StrictMath`). It
cannot reproduce numpy's random streams, so for the same seed it writes **different samples** than
the committed files, but the same `expected` blocks (they come from the noise-free truth;
`brief_glances_down` also draws its glance pattern at random, so its truth differs). Regenerating
therefore replaces every sample, which is why the committed Python output was kept; JUnit checks
that freshly generated fixtures pass their own `expected` and are byte-identical across runs. Its
motion model is documented at the top of that file: scripted head pose
(keyframes + glances) + natural sway (~0.5° OU process + breathing) + micro-movements (±1.5°,
up to 4°) + heading changes/head turns + an earbud mounting offset (pitch 8°, roll −3°) + white
sensor noise (0.05°) + delivery-time jitter (σ 4 ms, so the pipeline must rely on timestamps).

**Axes (D-011).** Head frame +X right ear, +Y nose, +Z up (unverified on hardware, S-05). Every
fixture states its axes explicitly in `config` (`forwardAxis` (-1,0,0), `lateralAxis` (0,1,0)),
equal to AlignCore's `HeadAxisConvention.airPodsDefault`; both test suites check that equality.
Under this convention a +20° chin-down pose has head-frame gravity (0, +0.342, −0.940) and a
+20° right-ear-down pose (+0.342, 0, −0.940).

## Scenarios

| File | What happens | Expected |
|---|---|---|
| `steady_neutral` | calibrate, 45 s neutral with sway, micro-movements, head turns | no reminders, no episodes |
| `gradual_forward_slouch` | drift to 24° forward over 10 s, hold 60 s, return | 1 `forward` reminder ≈ crossing + 30 s |
| `brief_glances_down` (20 Hz) | repeated 3–5 s glances to 26–34° forward | 0 reminders, 0 episodes |
| `lateral_right_tilt` (t starts at 5000 s) | 20° right tilt held 45 s | 1 `right` reminder |
| `cooldown_retrigger` (20 Hz, `sustainedDuration` 10, `reminderCooldown` 60) | three 22° forward tilts | reminders on tilts 1 and 3 only; 3 episodes |
| `calibration_too_much_movement` | ±9°/±4° movement during calibration | `tooMuchMovement`, final `needsCalibration` |
| `disconnect_mid_tilt` | sustained forward tilt; no samples 52–57 s | episode closed at the last sample before the gap (≈51.96 s) |
| `looking_up_backward` | 30° look-up held 42 s | 1 `backward` reminder (threshold 20°) |

## Format (schemaVersion 1)

```jsonc
{
  "schemaVersion": 1,
  "name": "gradual_forward_slouch",          // = file name without .json
  "description": "…",
  "generator": { "script": "…/generator.py", "version": "0.1.0", "seed": 102, "numpy": "2.5.4" },
  //   Java-generated: { "script": "…/Generator.java", "version": "0.1.0", "seed": 102, "runtime": "java 21.0.13" }
  "sampleRateHz": 25,                        // nominal; timestamps are authoritative
  "startTimestamp": 0.0,                     // t of the first sample (monotonic seconds)
  "config": { "forwardAxis": [-1,0,0], "lateralAxis": [0,1,0], "sustainedDuration": 10.0 },  // overrides; see below
  "baseline": null,                          // or { "gravity": [x,y,z], "version": 1, "sampleCount": 250 }
  "actions": [ { "t": 0.0, "type": "beginCalibration" } ],
  "truth": { … },                            // informational: keyframes, glances, gaps, mount, sway
  "expected": {
    "calibrationOutcomes": ["succeeded"],    // in order; "succeeded" or a CalibrationFailure raw value
    "reminders": [ { "t": 55.81, "direction": "forward" } ],
    "episodes": [ { "direction": "forward", "start": 25.81, "end": 92.5, "reminderTriggered": true } ],
    "finalState": "neutral",                 // PostureState case name after the last sample/action
    "tolerances": { "timeSeconds": 2.0 }     // for every expected t / start / end
  },
  "reference": { … },                        // exact output of the reference pipeline (parity check)
  "samples": [
    {"t":0.0,"q":[-0.076,-0.0221,-0.0465,0.9958],"g":[-0.05198,0.15071,-0.98721]}
  ]
}
```

### `config`
Keys are the Swift `PostureConfiguration` property names: `calibrationDuration`,
`calibrationMaxSpreadDegrees`, `minimumCalibrationSamples`, `forwardThresholdDegrees`,
`backwardThresholdDegrees`, `lateralThresholdDegrees`, `hysteresisDegrees`, `sustainedDuration`,
`reminderCooldown`, `smoothingTimeConstant`, `maxProcessingRateHz`, `maxSampleGap`, plus
`forwardAxis` / `lateralAxis` as `[x, y, z]`. Absent keys keep the `.default` value.

### `actions`
Applied in order **before the first sample whose `t` ≥ the action's `t`**; actions after the
last sample are applied at the end. Types: `beginCalibration`, `cancelCalibration`,
`resetCooldown`, `interrupt` (calls `interrupt(at: t)` and records its update).

### `samples`
- `t` — `MotionSample.timestamp` (seconds, strictly increasing, jittered; gaps are simply missing samples).
- `q` — `MotionSample.attitude` as `[x, y, z, w]` (Hamilton, like `CMQuaternion`), 4 decimals.
- `g` — `MotionSample.gravity` in the head frame, in g, 5 decimals. Optional: if absent the
  pipeline derives gravity from `q` assuming a Z-up world (`q.conjugate.rotate((0,0,-1))`).
- `r` — optional `rotationRate` `[x, y, z]` rad/s (not used by the pipeline; not written today).
- `sensorLocation` is not part of the format: the pipeline ignores it (earbud hand-off is not
  treated as an interrupt; see docs/research/algorithm-evaluation.md).

### `expected` vs `reference`
- `expected` is derived from the **noise-free scripted truth**, not from the detector: an
  episode starts when the true component first reaches its threshold, ends when it first falls
  below threshold − hysteresis, and a reminder is due at start + `sustainedDuration`. Counts,
  directions, `reminderTriggered`, outcomes and final state must match exactly; times within
  `tolerances.timeSeconds` (covers the ~0.5 s smoothing lag and noise).
- `reference` is the exact output of the reference implementation on the stored (rounded)
  samples: reminders (t, direction, deviationDegrees, sustainedSeconds), episodes (start, end,
  peakDeviationDegrees, reminderTriggered), calibrationOutcomes, finalState and
  stateTransitions (number of changes of PostureState case between consecutive updates).
  `producedBy` names the writer (`align_reference 0.1.0` = Python, `align-tools 0.1.0` = Java).
  Java asserts the same outcomes, counts, directions and transitions,
  timestamps within 1e-9 and rounded degree values within 1e-4 (today all eight committed blocks
  are reproduced bit for bit); Swift asserts the same counts/directions/outcomes/transitions,
  times within one sample period and degrees within 0.05°.

Regenerate fixtures (and therefore `reference`) whenever the reference algorithm changes, and
commit the reference (Java) and Swift changes together.
