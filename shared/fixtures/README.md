# Motion replay fixtures

`motion/*.json` are synthetic AirPods head-motion recordings with the outcomes the posture
pipeline must produce. The same files are replayed by the Java reference
(`analytics/align-tools`, JUnit) and by Swift (`ios/AlignKit/Tests/PostureDetectionTests`).

They are generated, not hand-edited. **The eight v1 fixtures were produced by the original Python
generator** (`align_reference/generator.py`, numpy 2.5.4; removed after the Java port, D-015, and
still in git history); their `generator` block says so. The five D-017 fixtures
(`nod_axis_calibration_*`, `calibration_brief_fidget`) were written by the Java generator
(`"runtime": "java 21.0.13"`), which is a port of the same motion model:

```sh
cd analytics/align-tools
./mvnw -q compile exec:java@generate                                # writes the Java-generated fixtures
./mvnw -q compile exec:java@generate -Dexec.args="--only nod_axis_calibration_up"   # just these
./mvnw -q compile exec:java@generate -Dexec.args="--out /tmp/fx"    # every scenario, elsewhere
./mvnw -q compile exec:java@rereference                             # recompute reference blocks only
./mvnw -q compile exec:java@rereference -Dexec.args="--check"       # report stale blocks, exit 1
```

Without `--only`, writing into `shared/fixtures/motion` skips the eight Python-generated fixtures,
so their samples are never replaced by accident. When the reference algorithm changes, run
`rereference`: it recomputes each fixture's `reference` block with the Java pipeline and rewrites
**only that block** (samples, `expected` and everything else stay byte for byte; a block whose
content is unchanged is left alone, so it keeps its `producedBy`). JUnit fails if any committed
block is stale.

(`mvnw.cmd` on Windows without Git Bash; only a JDK 21 is needed.) The Java generator
(`src/main/java/com/bachnguyennn/align/reference/Generator.java`) is seeded and deterministic for
a given seed on every JDK and platform (`SplittableRandom` + Box-Muller + `StrictMath`). It
cannot reproduce numpy's random streams, so for the same seed it writes **different samples** than
the committed files, but the same `expected` blocks (they come from the noise-free truth;
`brief_glances_down` also draws its glance pattern at random, so its truth differs). Regenerating
therefore replaces every sample, which is why the committed Python output was kept; JUnit checks
that freshly generated fixtures pass their own `expected` and are byte-identical across runs, and
that the committed Java-generated fixtures are reproduced exactly. Its
motion model is documented at the top of that file: scripted head pose
(keyframes + glances) + natural sway (~0.5° OU process + breathing) + micro-movements (±1.5°,
up to 4°) + heading changes/head turns + an earbud mounting offset (pitch 8°, roll −3°, and
since D-017 an optional **mount yaw**, default 0) + white sensor noise (0.05°) + delivery-time
jitter (σ 4 ms, so the pipeline must rely on timestamps).

**Mount yaw (D-017).** `mountYaw` rotates the device frame relative to the head about the head's
up axis (`lateralAxis × forwardAxis`), applied before the pitch/roll offset: Mount =
Yaw(mountYaw) · Pitch(mountPitch about forwardAxis) · Roll(mountRoll about lateralAxis). It is
recorded as `truth.mountDegrees.yaw` (absent = 0; with 0 the samples are bit for bit those of the
v1 model). A positive mount yaw is learned as a positive yaw (see `learnedAxes` below); with the
default 8°/−3° pitch/roll the learned yaw differs from `mountYaw` by a few tenths of a degree
(25° → 25.42°), because yaw is measured between axes projected onto the baseline plane.

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
| `nod_axis_calibration_yawed_earbud` (Java) | earbud yawed 25°; calibrate, `beginAxisCalibration` at 11 s, 25° nod down and back (12–14.6 s), then 20° forward from 20–23 s held to 68 s | axis `succeeded`, learned yaw 25.42 ± 3°, 1 `forward` reminder, \|lateral\| ≤ 3° during 25–66 s (default axes read ≈ 8.5°) |
| `nod_axis_calibration_up` (Java) | earbud yawed −15°; nod **up** to −20° and back | axis `succeeded`, yaw −14.58 ± 3°, sign kept (no reminders) |
| `nod_axis_calibration_sideways_rejected` (Java) | right ear to shoulder 20° and back instead of a nod | axis `inconsistentMotion`, no learned axes |
| `nod_axis_calibration_no_nod` (Java) | keeps still during the axis calibration | axis `noNodDetected` after 8 s, no learned axes |
| `calibration_brief_fidget` (Java) | one 1 s fidget to 10° at 4 s during the neutral calibration | `succeeded` with quantile 0.9 (the v1 rule, quantile 1.0, rejects it) |
| `calibration_slow_slouch` (Java) | steady slouch from 0 to 10° forward over the 10 s neutral calibration | `tooMuchMovement` from the D-020 drift rule (the spread rule alone accepts it), final `needsCalibration` |

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
  "baseline": null,                          // or { "gravity": [x,y,z], "version": 1, "sampleCount": 250,
                                             //       "learnedAxes": { "forwardAxis": [..], "lateralAxis": [..] } }  (learnedAxes optional)
  "actions": [ { "t": 0.0, "type": "beginCalibration" } ],
  "truth": { … },                            // informational: keyframes, glances, gaps, mount, sway
  "expected": {
    "calibrationOutcomes": ["succeeded"],    // in order; "succeeded" or a CalibrationFailure raw value
    "reminders": [ { "t": 55.81, "direction": "forward" } ],
    "episodes": [ { "direction": "forward", "start": 25.81, "end": 92.5, "reminderTriggered": true } ],
    "finalState": "neutral",                 // PostureState case name after the last sample/action
    "tolerances": { "timeSeconds": 2.0 },    // for every expected t / start / end
    // optional, D-017 (only in fixtures with beginAxisCalibration, except maxAbsLateral):
    "axisCalibrationOutcomes": ["succeeded"],                  // "succeeded" or an AxisCalibrationFailure raw value
    "learnedAxes": { "present": true, "yawDegrees": 25.42, "toleranceDegrees": 3.0 },  // or { "present": false }
    "maxAbsLateral": { "from": 25.0, "to": 66.0, "degrees": 3.0 }   // |tilt.lateralDegrees| bound on updates in [from, to]
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
`forwardAxis` / `lateralAxis` as `[x, y, z]`, since D-017 `calibrationSpreadQuantile`,
`axisCalibrationDuration`, `axisCalibrationMinimumNodDegrees`, `axisCalibrationMaxYawDegrees`,
`axisCalibrationMaxOffAxisRatio`, and since D-020 `calibrationMaxDriftDegrees`,
`calibrationDriftWindow`. Absent keys keep the `.default` value.

### `actions`
Applied in order **before the first sample whose `t` ≥ the action's `t`**; actions after the
last sample are applied at the end. Types: `beginCalibration`, `cancelCalibration`,
`beginAxisCalibration`, `cancelAxisCalibration`, `clearLearnedAxes` (D-017), `resetCooldown`,
`interrupt` (calls `interrupt(at: t)` and records its update).

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
  D-017 fields: `axisCalibrationOutcomes` must match exactly; `learnedAxes.present` says whether
  the replay ends with learned axes, and `yawDegrees` is the yaw a perfect nod learns for the
  scripted mount (signed angle from the configured forward axis to the learned one, both
  projected onto the baseline plane; positive toward the default lateral axis, i.e. a right-hand
  rotation about the baseline gravity), checked within `toleranceDegrees` (3°, covers sway during
  the nod); `maxAbsLateral` bounds the reported lateral tilt over a time window (used to show that
  learned axes remove earbud-yaw crosstalk).
- `reference` is the exact output of the reference implementation on the stored (rounded)
  samples: reminders (t, direction, deviationDegrees, sustainedSeconds), episodes (start, end,
  peakDeviationDegrees, reminderTriggered), calibrationOutcomes, finalState and
  stateTransitions (number of changes of PostureState case between consecutive updates).
  When an axis calibration finished during the replay it also has `axisCalibrationOutcomes` and
  `learnedAxes` (`{forwardAxis, lateralAxis}` rounded to 6 decimals, or `null`); blocks of
  fixtures without one keep the v1 layout.
  `producedBy` names the writer (`align_reference 0.1.0` = Python, `align-tools 0.1.0` = Java).
  Java asserts the same outcomes, counts, directions and transitions,
  timestamps within 1e-9 and rounded degree values within 1e-4 (today every committed block,
  including the eight Python ones, is reproduced bit for bit); Swift asserts the same
  counts/directions/outcomes/transitions, times within one sample period, degrees within 0.05°
  and learned axis components within 1e-4.

Run `rereference` (above) whenever the reference algorithm changes, and commit the reference
(Java) and Swift changes together. D-017 changed no v1 reference block: with the quantile rule
every v1 fixture keeps its outcome (`calibration_too_much_movement` still fails: its ±9° nodding
leaves far fewer than 90 % of the samples within 5°), and a calibration whose samples are all
within the spread produces bit for bit the v1 baseline. D-020 (calibration drift rule) changed no
reference block either (`rereference --check`: 0 differ); no committed fixture drifts by more
than 3° between the first and last 2 s of its calibration.

## Recordings (D-017 (d))

A **recording** is a real motion session captured by the app's opt-in diagnostic recorder, for
tuning on real data. It uses the fixture schema without the parts that only synthetic data can
have: `schemaVersion`, `name`, `sampleRateHz`, `startTimestamp`, `samples` (same sample format;
`g` optional), optional `config` (the configuration in use when recording), optional `baseline`
(including `learnedAxes`) and optional `actions` (e.g. the `beginCalibration` /
`beginAxisCalibration` the user triggered while recording), plus a `recording` block; and **no**
`expected`, `reference`, `truth` or `generator`:

```jsonc
{
  "schemaVersion": 1,
  "name": "2026-11-02-desk-session",
  "recording": {
    "appVersion": "1.0 (12)",              // CFBundleShortVersionString (CFBundleVersion)
    "device": "iPhone17,1",                  // hardware model identifier
    "headphones": "AirPods Pro (2nd generation)",
    "notes": "seated at desk, laptop, slouched twice",   // free text typed by the user, optional
    "createdAt": "2026-11-02T14:03:00Z"      // ISO 8601, UTC
  },
  "sampleRateHz": 25,
  "startTimestamp": 1234.56,
  "config": { "forwardThresholdDegrees": 15.0 },
  "baseline": { "gravity": [0.05, 0.14, -0.99], "version": 3, "sampleCount": 251 },
  "actions": [ { "t": 1240.0, "type": "beginAxisCalibration" } ],
  "samples": [ {"t":1234.56,"q":[-0.076,-0.0221,-0.0465,0.9958],"g":[-0.05198,0.15071,-0.98721]} ]
}
```

Replay one or more recordings (or fixtures) and print a timeline summary: calibration outcomes,
learned axes and their yaw from the configured axes, tilt percentiles per axis, entries into
`deviating`, episodes, reminders, sample rate and the largest gap. `--set key=value` overrides a
configuration value (JSON value, keys as in `config`), e.g. to try a threshold on real data:

```sh
cd analytics/align-tools
./mvnw -q compile exec:java@replay -Dexec.args="../../shared/fixtures/recordings/my-session.json"
./mvnw -q compile exec:java@replay -Dexec.args="--set forwardThresholdDegrees=12 a.json b.json"
```

Where recordings go and how to handle them: `recordings/README.md`.
