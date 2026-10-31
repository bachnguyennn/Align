# Algorithm agent report (A-01 … A-04)

Branch: `worktree-agent-a4b525d6d622bbb15`. Status: Python verified locally. **Swift written but
never compiled or run** (no Swift toolchain on this Windows machine), so A-02/A-03 are at most
`in review` until CI runs.

## Deliverables

| Task | Paths |
|---|---|
| A-01 Python reference + generator + fixtures | `analytics/requirements.txt`, `analytics/experiments/align_reference/` (`geometry`, `model`, `motion_filter`, `calibration`, `tilt`, `detector`, `reminder`, `monitor`, `fixtures`, `pose`, `generator`, `evaluate`), `analytics/experiments/tests/`, `shared/fixtures/motion/*.json` (8 fixtures, 1082 KiB), `shared/fixtures/README.md` |
| A-02 Swift pipeline | `ios/AlignKit/Sources/PostureDetection/`: `PostureMonitor`, `MotionFilter`, `CalibrationService`, `TiltEstimator`, `PostureDetector`, `ReminderDecisionEngine`, `PostureDetectionConstants` (placeholder removed). Pure Foundation. |
| A-03 Swift tests | `ios/AlignKit/Tests/PostureDetectionTests/`: `TiltEstimatorTests`, `ComponentTests` (filter, calibration, detector, reminder), `PostureMonitorTests`, `FixtureReplayTests` (Codable fixture model, replays all 8 fixtures, checks `expected` and Python `reference` parity), `TestSupport`. Fixtures are found from `#filePath` by walking up to `shared/fixtures/motion` (no SwiftPM resources). |
| A-04 Evaluation | `docs/research/algorithm-evaluation.md`, `analytics/experiments/results/evaluation.md` (raw output) |

## Tests actually run

- `analytics/.venv/Scripts/python -m pytest analytics/experiments/tests -q` → **103 passed**
  (Python 3.12, numpy 2.5.4, pytest 9.2.0). This covers the sign derivation, the D-011
  convention (forward × lateral = (0,0,−1); gravity cross-checks (0, +0.342, −0.940) and
  (+0.342, 0, −0.940)), components, monitor behaviour (interrupt, gap, decimation, version
  increment, recalibration, cooldown) and all 8 fixtures against `expected` and `reference`.
  Generator determinism is also checked.
- `python -m align_reference.evaluate --seeds 20` → completed in 188 s; numbers are in the
  evaluation doc. Headline results (synthetic): 60/60 tilt scenarios produced exactly one
  reminder, about 0.5 s after crossing + 30 s; 0 false reminders and 0 false episodes in 35.7
  monitored minutes of neutral and glance data; one stable episode for a hold at the threshold
  with the default 3° hysteresis.
- **Swift: not compiled, not run.** I checked every AlignCore signature by hand. Swift tests
  that depend on D-011 being on main: `TiltEstimatorTests.testAirPodsDefaultIsD011WithCrossCheckGravity`
  and `FixtureReplayTests.testFixtureAxesMatchAlignCoreDefault`. Both **fail on this branch as
  is**, because its AlignCore still has the old default; they should pass after merging onto
  main with D-011. All other tests are independent of the default: fixtures state their axes
  explicitly in `config`.

## Behaviour choices (within the §2 contract)

- `state`: `.unavailable` before the first sample and after `interrupt`/gap; `.calibrating`
  takes precedence; `since` in `.deviating`/`.sustainedTilt` is the **deviation onset**.
- Tilt is reported whenever a baseline exists, including during recalibration (against the old
  baseline). During calibration the detector is paused.
- `beginCalibration()` during a sustained tilt closes the episode at the last processed
  timestamp and delivers it with the next update.
- A failed or cancelled calibration keeps the previous baseline.
- `interrupt` keeps the reminder cooldown. Only `resetCooldown()` clears it.
- Samples with non-increasing timestamps or zero gravity are ignored. A missing `gravity` is
  derived from `attitude` (Z-up world).
- Decimation uses a phase-accumulating schedule (25 Hz capped at 10 Hz gives 10 Hz).
- Duration comparisons use a 1e-9 s epsilon so `45.04 − 15.04` counts as 30 s.
- **Baseline-plane axes**: configured axes are projected onto the plane ⊥ baseline gravity
  before the dot product. This is identical to the plain projection when the axes are already
  perpendicular, and removes the cos(offset) error of a pitched or rolled earbud (evaluation
  table: 1.2° error at a 20° offset becomes 0). This is a refinement of D-005 the Lead should
  record.
- `sensorLocation` changes (earbud hand-off) are **not** treated as interrupts; reasoning is in
  the evaluation doc.
- `ReminderDecision.deviationDegrees` and `PostureEpisode.peakDeviationDegrees` are the
  component in the episode direction (degrees), not `totalDegrees`.

## Known limitations

Synthetic-only evaluation. Axes unverified (S-05). Earbud yaw and combined pitch+roll crosstalk
are uncompensated (≤ 1.2° per 20°). Direction is locked at onset. No activity gating. No
watchdog: the app must call `interrupt`. Fixtures total 1082 KiB, slightly above the 1 MB aim;
the alternative was dropping samples below 20 Hz. `minimumCalibrationSamples` = 100 is
borderline at 10 Hz processing. Placeholder deletions landed in the D-011 commit rather than the
Swift commit (cosmetic).

## Proposed AlignCore contract changes (for decisions.md)

1. **Deferred reminder (proposal).** Today, an episode that becomes sustained inside the
   cooldown never reminds. Proposal: allow the single per-episode reminder on the first sustained
   update after the cooldown expires. It needs a contract wording change only; no type change.
2. **Record baseline-plane axis projection** as part of D-005 (already implemented).
3. Optional: `PostureState` could expose a public `kind`/`direction` helper. I added one only in
   tests (`kindName`); the Frontend may want it in AlignCore.
4. Optional later: a per-`SensorLocation` baseline offset, if S-05 shows the earbuds disagree.

## Messages

**Frontend**
- Bind UI to `PostureUpdate.state`: `unavailable` (no data: show connection status),
  `needsCalibration` (prompt calibration), `calibrating(progress)` (progress ring, 10 s, ask
  the user to sit tall and hold still), `neutral`, `deviating(direction, since)` (a gentle
  indicator only; glances do this about 4–5 times a minute), and `sustainedTilt(direction, since)`.
  `since` is the deviation onset, so "tilted for N s" = `timestamp − since`.
- Fire notifications and haptics only on `update.reminder != nil`. Persist `completedEpisode`
  as `PostureEvent`. `calibrationOutcome` appears on exactly one update per attempt; on
  `.succeeded(baseline)` store the baseline (its `version` increments).
- Call `interrupt(at:)` on disconnect, pause or stop, and add a watchdog: no sample for more than
  1–2 s means interrupt. Call `resetCooldown()` at the start of a session.
- Sensitivity presets (thresholds only; keep hysteresis 3°, τ 0.5 s): Relaxed 20/25/20°,
  sustained 60 s; Standard = defaults (15/20/15°, 30 s); Strict 12/18/12°, sustained 20 s.
  Reminder frequency is separate (cooldown 2/5/10 min). If `maxProcessingRateHz` is ever set to
  10, lower `minimumCalibrationSamples` to about 60.
- Copy: "head tilted forward", never "forward head posture" (see the evaluation doc).

**Sensor**
- PostureDetection reads only `gravity` (falling back to `attitude` with a Z-up world) and
  `timestamp`. Timestamps must be monotonic seconds; jitter is fine.
- Axes are taken from `PostureConfiguration.axes` (D-011: +X right ear, +Y nose, +Z up;
  forward (−1,0,0), lateral (0,1,0)). Cross-check values: +20° chin-down ⇒ g ≈ (0, +0.342,
  −0.940); +20° right-ear-down ⇒ g ≈ (+0.342, 0, −0.940). Please verify both on hardware in
  S-05, and record raw sessions (t, q, g, sensorLocation) so we can add real fixtures.
- Please report whether gravity steps at an earbud hand-off.

---

# D-015: Java port of the reference tools

Branch: `worktree-agent-a0c78177f3a705f76`. Status: done and green locally; the new `java` CI
job has not run yet. Python code and the committed fixtures are unchanged.

## Deliverables

| Python | Java (`analytics/align-tools`, package `com.bachnguyennn.align.reference`) |
|---|---|
| `geometry.py` | `Geometry` (`Vec3`, `Quat` records + static functions) |
| `model.py` | `Model` (`TIME_EPSILON`), `TiltDirection`, `CalibrationFailure`, `PostureState` (+ `Kind`), `MotionSample`, `TiltEstimate`, `NeutralBaseline`, `CalibrationOutcome`, `ReminderDecision`, `PostureEpisode`, `PostureUpdate`, `HeadAxisConvention`, `PostureConfiguration` (record + builder; `fromOverrides`, `replacing`) |
| `motion_filter.py`, `calibration.py`, `tilt.py`, `detector.py`, `reminder.py`, `monitor.py`, `pose.py` | `MotionFilter`, `CalibrationService`, `Tilt`, `PostureDetector`, `ReminderDecisionEngine`, `PostureMonitor` (incl. the D-016 deferred reminder), `Pose` |
| `fixtures.py` | `Fixtures` (load, replay with actions, `checkExpected`, `referenceBlock`; the repo root is found by walking up to `shared/fixtures/motion`) |
| `generator.py` | `Generator` + `ScenarioSpec`; CLI `./mvnw -q compile exec:java@generate [-Dexec.args="--out <dir>"]` |
| `evaluate.py` | `Evaluate`; CLI `./mvnw -q compile exec:java@evaluate [-Dexec.args="--seeds N --out PATH"]`; report in `analytics/align-tools/results/evaluation.md` |
| (json, round, format) | `Json`, `PythonFormat`: Python `json.dumps` layout, float `repr`, `round` and `:.nf` (half-even on the exact binary value) |
| `tests/*.py` | `ComponentsTest`, `GeometryTiltTest`, `MonitorTest`, `FixturesTest`, `EvaluateTest`, plus `GeneratorTest` and `PythonFormatTest` |

Maven 3.9.16 through the wrapper (`mvnw`, `mvnw.cmd`), Java 21, Jackson 2.22.4, JUnit 5.14.4,
Surefire 3.6.1. The only runtime dependency is `jackson-databind`. The pipeline uses
`StrictMath`, so its results are the same on every JVM and platform. CI: new `java` job
(ubuntu-24.04, Temurin 21, `./mvnw -B -ntp verify`, test count as a notice).

## Tests actually run

- `./mvnw -B -ntp verify` (Temurin 21.0.13, Windows 11) → **Tests run: 177, Failures: 0,
  Errors: 0, Skipped: 0**.
- `analytics/.venv/Scripts/python -m pytest analytics/experiments/tests -q` → **104 passed**
  (Python unchanged, numpy 2.5.4).

## Parity evidence

- **Committed fixtures (written by Python), replayed by Java.** All 8 reproduce the stored
  `reference` block exactly, apart from `producedBy` (max |Δt| = 0, max |Δ rounded value| = 0),
  and all 8 pass `expected`. JUnit asserts the required tolerances (1e-9 s, 1e-4) and prints one
  `parity …` line per fixture:

  | fixture | reminders | episodes | stateTransitions | match |
  |---|---|---|---|---|
  | brief_glances_down | 0 | 0 | 11 | exact |
  | calibration_too_much_movement | 0 | 0 | 1 | exact |
  | cooldown_retrigger | 2 | 3 | 10 | exact |
  | disconnect_mid_tilt | 1 | 1 | 5 | exact |
  | gradual_forward_slouch | 1 | 1 | 4 | exact |
  | lateral_right_tilt | 1 | 1 | 4 | exact |
  | looking_up_backward | 1 | 1 | 4 | exact |
  | steady_neutral | 0 | 0 | 1 | exact |

- **Java-generated fixtures, replayed by Python** (checked once by hand, not in CI): Python
  reproduces all 8 Java `reference` blocks exactly, and all 8 pass `expected`.
- **File format.** Writing each committed fixture back out with the Java writer reproduces the
  file byte for byte (JUnit `fixtureFileLayoutRoundTrips`).
- **Generator truth.** For 7 of 8 scenarios the Java generator writes the same `expected`,
  `description`, `config`, `actions`, `sampleRateHz` and `startTimestamp` as the committed files
  (JUnit). `brief_glances_down` draws its glances at random, so its truth differs; its `expected`
  is empty either way.
- **Evaluation.** The axis-projection table (no random data) is identical to the Python report
  (JUnit). Re-running the Python evaluation reproduced the committed Python report apart from the
  timing lines, so that report is current.

## What differs from Python (by necessity)

- The generator cannot reproduce numpy's random streams. It uses `SplittableRandom` (Box-Muller
  normals, inverse-CDF exponentials) and writes `"generator": {"script", "version", "seed",
  "runtime": "java 21.0.13"}` instead of `"numpy"`. The same seed gives byte-identical output
  (JUnit), but different samples from the committed fixtures, so **the committed fixtures were
  not regenerated**.
- Every table in the Java evaluation report except the axis projection comes from Java-generated
  data and differs from the Python report within noise. Examples: threshold 20° with an 18° hold
  gives 0/10 in Java and 2/10 in Python; calibration with 3° sway succeeds 8/20 in Java and 13/20
  in Python. The conclusions are unchanged. The report header says where the numbers come from.
- `producedBy` is `align-tools 0.1.0` in reference blocks written by Java.
- `test_generator_is_deterministic` (numpy) is replaced by `GeneratorTest`, which writes to a
  temporary directory and never to `shared/fixtures`.

## Discrepancies and bugs found (not fixed; Python and Swift left as they are)

1. **The floating-point edge test does not test the edge.** `model.py`,
   `PostureDetectionConstants.swift`, `test_floating_point_duration_edge_counts_as_elapsed` and the
   Swift `ComponentTests` all say `45.04 − 15.04 = 29.999999999999996`. In IEEE doubles it is
   exactly `30.0` (checked in CPython and Java), so the test passes even without `TIME_EPSILON`.
   A pair such as `32.05 − 2.05` (< 30) would exercise it. The Java test mirrors the Python test
   as written.
2. **Outdated docstring.** `reminder.py` says the engine is "called once per episode, on the
   update where the tilt becomes sustained". Since D-016 the monitor calls it on every sustained
   update until the episode has reminded. The Java doc comment describes the current behaviour.
3. I found no behavioural difference between Python and Swift in `PostureMonitor`,
   `PostureDetector`, `MotionFilter`, `CalibrationService`, `TiltEstimator` or
   `ReminderDecisionEngine`. I read them side by side: the same expressions in the same order.

## For the Lead

- Once the `java` job is green, `analytics/experiments`, `analytics/requirements.txt` and the
  `python` CI job can be removed. After that, drop the Python mentions from
  `shared/fixtures/README.md`, the README test table and `docs/agents/test-plan.md`.
- If the fixtures are regenerated with Java later, Swift's `FixtureReplayTests` need no change:
  they read neither `generator` nor `producedBy`.

# D-017 (a, b): guided-nod axis calibration and calibration spread quantile

Branch `worktree-agent-a32daae5820c5bf01`, based on `main` at `0af3f4d` (the Lead's AlignCore
commit). AlignCore was not changed; the five new configuration defaults were kept (evidence
below).

## Deliverables

- **Java reference** (`analytics/align-tools`): `AxisCalibrationFailure`, `AxisCalibrationOutcome`,
  `NeutralBaseline.learnedAxes`, `PostureUpdate.axisCalibrationOutcome` and the five
  `PostureConfiguration` fields mirrored; `AxisCalibrationService`; `PostureMonitor.effectiveAxes()`,
  `beginAxisCalibration()`, `cancelAxisCalibration()`, `clearLearnedAxes()`; tilt uses the effective
  axes; quantile spread rule in `CalibrationService`.
- **Swift** (`ios/AlignKit/Sources/PostureDetection`): `AxisCalibrationService.swift` (new),
  `PostureMonitor.swift` (API exactly as in sensor-contracts.md), `CalibrationService.swift`,
  `PostureDetectionConstants.swift`, `TiltEstimator.swift` (doc only).
- **Generator**: `mountYaw` (rotation about the head's up axis, default 0 = bit for bit the v1
  model) and five Java-generated fixtures: `nod_axis_calibration_yawed_earbud`,
  `nod_axis_calibration_up`, `nod_axis_calibration_sideways_rejected`, `nod_axis_calibration_no_nod`,
  `calibration_brief_fidget`. New `expected` fields `axisCalibrationOutcomes`, `learnedAxes`
  (`present`, `yawDegrees`, `toleranceDegrees`) and `maxAbsLateral`; `reference` gains
  `axisCalibrationOutcomes` and `learnedAxes` only when an axis calibration finished. New actions
  `beginAxisCalibration`, `cancelAxisCalibration`, `clearLearnedAxes`. Without `--only` the
  generator no longer overwrites the eight Python-generated fixtures.
- **Tools**: `exec:java@replay` (timeline summary of recordings or fixtures, `--set key=value`
  overrides) and `exec:java@rereference` (recompute reference blocks, keep samples; `--check`).
- **Tests**: JUnit `AxisCalibrationTest` (19), quantile tests in `ComponentsTest`, new fixture,
  generator and evaluation tests, `ReplayToolsTest`; Swift `AxisCalibrationTests` (the same 19
  cases), quantile tests in `ComponentTests`, `FixtureReplayTests` for the new fixtures, actions
  and expected/reference fields.
- **Docs**: `shared/fixtures/README.md` (new fixtures, mount yaw, fields, recording format,
  tools), `shared/fixtures/recordings/README.md` (no data, only where real recordings go),
  `docs/research/algorithm-evaluation.md` (D-017 section, recommendations, limitations),
  `analytics/align-tools/results/evaluation.md` (regenerated, 20 seeds).

## Tests actually run

- `./mvnw -B -ntp verify` (JDK 21.0.13, Windows 11): **284 JUnit tests, 0 failures** (177 before).
- **Swift was not compiled**: there is no Swift toolchain on this machine. The Swift code mirrors
  the Java line by line and uses only APIs that exist in AlignCore, Foundation and XCTest, but
  its first compile happens in CI.

## Algorithm (refinements within the contract)

- Head rotation per smoothed sample: `head = −rotationVector(g0, g)`, as in the tilt estimate.
  Samples with |head| ≥ 3° are fitted (`axisCalibrationMotionFloorDegrees`).
- **Forward line = principal axis** of the fitted vectors in the baseline plane, with basis
  `e1` = configured forward axis projected onto the plane and `e2` = normalized(`g0 × e1`); angle
  `0.5·atan2(2·Sab, Saa − Sbb)` ∈ (−90°, 90°], so `forward · e1 ≥ 0` (sign from the default; a nod
  down or up both work). Lateral = normalized(`g0 × forward`); for the defaults with
  `g0 = (0, 0, −1)` this gives exactly forward (−1, 0, 0), lateral (0, 1, 0) (asserted in both
  suites). Chosen over the sign-aligned sum by evaluation (mean yaw error 1.00° vs 1.11° at 0.5°
  sway, 3.96° vs 4.74° at 2°). A centred principal axis was also tried (0.86° at 0.5° sway) but
  accepted fewer nods at high sway (14/20 vs 19/20), so it stays evaluation-only in Java.
- Off-axis ratio = Σ|v·lateral| ÷ Σ|v·forward| over the fitted samples; yaw = fitted angle.
- Finish: first update with |head| ≤ 5° after a peak ≥ `axisCalibrationMinimumNodDegrees`, else at
  `axisCalibrationDuration`. The floor and return levels are capped at half the minimum nod, so a
  configured minimum below 6° still works.
- Neutral calibration: the inliers are the samples within `calibrationMaxSpreadDegrees` of the
  plain mean; it fails unless inliers ≥ quantile × count (1e-9 tolerance, so 225/250 = 0.9
  passes). **Baseline = inlier mean**, so an accepted fidget does not bias the baseline (0.5°
  error, the same as without a fidget). With every sample an inlier this is bit for bit the v1
  mean.

## Contract interpretations (identical in Java and Swift)

1. `beginAxisCalibration()` without a baseline still cancels a neutral calibration in progress
   (the contract says it cancels one) and closes an open episode; `.needsBaseline` is delivered on
   the next update of any kind (`process`, passive or not, or `interrupt`).
2. `beginCalibration()` cancels an axis calibration in progress without an outcome (symmetric, so
   two calibrations never run at once). `cancelAxisCalibration()` gives no outcome.
3. `clearLearnedAxes()` keeps the baseline `version` (it is not a calibration).
4. If the head never comes back near neutral, the attempt ends at `axisCalibrationDuration` and,
   with a valid peak, is still fitted (a nod held down is a valid line); only the absence of a
   valid peak gives `.noNodDetected`.
5. The update carrying a successful axis outcome already reports its tilt with the new axes, as
   the neutral calibration's outcome update uses the new baseline.
6. Yaw and sign are always measured against `configuration.axes`, never against earlier learned
   axes, so repeated nods do not accumulate.
7. Lateral comes from geometry (`g0 × forward`), not from the configured lateral axis. For any
   right-handed device frame this is the physical right-ear-down axis.
8. Java's checks are written `!(x <= limit)` so that a NaN is rejected exactly like Swift's `guard`.

## Evaluation headline numbers (synthetic data only)

- **Crosstalk vs earbud yaw** (20° forward hold): default axes read 3.4° / 6.8° / 9.9° / 12.8° of
  lateral at 10° / 20° / 30° / 40° of yaw, and a 16° hold is reminded only 2/10 (30°) and 0/10
  (40°). With learned axes: 0.40° at every yaw (the synthetic sway) and 10/10. Noise-free, the
  learned axes read 20.000° / 0.000° even with the 8°/−3° pitch/roll offset.
- **Nod success** (earbud yaw 20°): 20° and 30° nods 20/20 up to 2° sway, 15/16 and 16/16 at 3°;
  learned yaw within 1.0° / 0.7° on average at 0.5° sway (4.0° / 2.7° at 2° sway). 8° and 12°
  nods are mostly rejected (smoothing attenuates the peak below 12°).
- **False acceptance**: ear-to-shoulder, 60° diagonal and circular head roll 0/20 accepted
  (`inconsistentMotion`); head turns 0/20 (`noNodDetected`); a 30° diagonal is accepted and
  learned as 30° of yaw (indistinguishable from a yawed earbud).
- **Quantile**: 0.9 kept. It accepts a single 1 s fidget to 10° or 20° 20/20 (v1: 0/20) and 2°
  sway 20/20, and still rejects the fixture's nodding 20/20 and two fidgets 20/20; 0.8 starts
  accepting users who look around (rejects only 7/20).
- Defaults kept: minimum nod 12° (lower would accept small nods with 9–13° yaw errors), max yaw
  45° (supports earbud yaw up to 40°, rejects 60° diagonals), off-axis ratio 0.35, duration 8 s,
  quantile 0.9.

## Existing fixtures

No sample and **no reference block changed**: `rereference --check` reports 0 stale blocks. All
v1 outcomes are unchanged under the quantile rule; `calibration_too_much_movement` still fails
(its ±9° nodding leaves far fewer than 90 % of the samples within 5°), and every v1 calibration
had all samples within the spread, so its baseline is bit for bit the v1 one. The JUnit fixture
size limit was raised from 1.25 to 2 MiB (the total is now about 1.4 MiB).

## Open issues and proposals

1. **Slow drift during the neutral calibration is not detected.** Slouching 10° over the 10 s is
   accepted 11/20 times with quantile 0.9 (4/20 with v1), biasing the baseline by ≈ 4.4°.
   Proposal for decisions.md: also fail `.tooMuchMovement` when the means of the first and last
   2 s differ by more than about 3°. Not implemented (it changes the contract).
2. **The UI must ask for a deliberate 20–30° nod**; 12° nods rarely pass after smoothing, and with
   large sway one nod gives 4–6° yaw errors (up to 12–18°). Averaging two nods would roughly halve
   that if real data shows high sway.
3. If S-05 finds the default forward and lateral axes **swapped**, every correct nod is rejected as
   more than 45° off, so the default convention must still be confirmed.
4. **Earbud hand-off**: learned axes, like the baseline, belong to one earbud's fit.
5. Swift compiles only in CI (see above).
6. Recorded sessions can be replayed (`exec:java@replay`), but recordings turned into fixtures
   are not wired into the tests yet (the suites expect `motion/` to contain generator scenarios
   only); suggested: a separate `recorded/` folder.

# A-07 / D-020: neutral calibration drift rule

Based on `main` at `e4e2a17` (AlignCore `calibrationMaxDriftDegrees` = 3, `calibrationDriftWindow`
= 2). Defaults confirmed, not changed.

## Deliverables

- `CalibrationService` (Java and Swift, identical): after the spread rule, `tooMuchMovement` if
  the normalized mean gravity of the samples with t − start ≤ window and that of the samples with
  last − t ≤ window are more than `calibrationMaxDriftDegrees` apart (`driftDegrees`, public for
  tests). Window edges are inclusive with the usual 1e-9 time tolerance; the comparison is
  `!(drift <= limit)` so NaN is rejected the same way in both. Java `PostureConfiguration` mirrors
  the two fields (fixture keys `calibrationMaxDriftDegrees`, `calibrationDriftWindow`; the Swift
  replay test reads them too).
- Scenario and Java-generated fixture `calibration_slow_slouch`: a steady 0→10° slouch over the
  10 s calibration (ten short eased keyframe segments). The spread rule alone accepts it (10/10
  seeds checked), the drift rule rejects it (10/10): expected `tooMuchMovement`,
  `needsCalibration`. A first version with one cosine-eased ramp was rejected by the spread
  rule already (samples cluster at both ends), so it did not test the new rule.
- Tests: JUnit `calibrationDriftRejectsASlowSlouch`, `driftWindowsIncludeTheirEdgesAndUseTimestamps`,
  `slowSlouchFixtureIsRejectedByTheDriftRule`, `driftTableRendersAndRejectsASlouchButNotAStillUser`,
  plus the parameterized fixture tests for the new file. Swift: `testDriftRejectsASlowSlouch`,
  `testDriftWindowsIncludeTheirEdgesAndUseTimestamps`, `testCalibrationSlowSlouch`,
  `testSlowSlouchFixtureIsRejectedByTheDriftRule`.
- Evaluation table "D-020" in `results/evaluation.md` and `docs/research/algorithm-evaluation.md`.

## Tests actually run

`./mvnw -B -ntp verify`: **299 JUnit tests, 0 failures** (284 before). Swift not compiled
locally (no toolchain); the changes are the drift helper in `CalibrationService.swift` and tests.

## Existing fixtures

`rereference --check`: 0 of the 13 previous fixtures differ, so no reference block was
rewritten; every committed calibration drifts less than 3° between its first and last 2 s.

## Evidence for the defaults

Rejections out of 20: steady slouch 0° / 3° / 5° / 10° over the 10 s → 0 / 4 / 20 / 20 with
3° / 2 s (spread rule alone: 0 / 0 / 0 / 1). Still users at sway 0.5° / 1° / 1.5° / 2° / 3° →
0 / 0 / 4 / 7 / 10 after the inlier revision below (spread rule alone: 0 / 0 / 0 / 0 / 5). 3° / 3 s halves the false rejections
at 2° sway (4/20) but misses 4/20 of the 5° slouches; 4° / 2 s misses 10/20; 2° / 2 s rejects
4/20 still users already at 1° sway. Kept 3° / 2 s; switch to 3° / 3 s if real recordings show
still users with 1.5–2° of sway.

## Side effect on the D-017 quantile table

With the drift rule in place, the regenerated D-017 (iv) table accepts fewer very unsteady
users (still, sway 2°: 14/20, was 20/20; sway 3°: 10/20, was 15/20) and rejects the eased slow
slouch 20/20 (was 9/20). The quantile choice (0.9) is unaffected: it still decides the fidget
rows. With the first version of the rule (all samples in a window), a 1 s fidget inside the
first or last 2 s failed (18/20 accepted); the inlier-only revision below fixes that.

## Revision: window means from spread-rule inliers (contract at 9c8be49)

Accepted proposal. The branch was rebased onto `main` at `9c8be49` (fast-forward was not
possible: `main` had only the contract commit, the four D-020 commits were not on it yet).

- `driftDegrees` (Java and Swift) now takes the spread-rule inlier mask: only inliers are
  averaged, the windows are still measured from the first and last timestamps of all samples,
  and an empty window returns NaN, which the existing `!(drift <= limit)` check turns into
  `.tooMuchMovement` in both languages. The convenience form without a mask (Java overload,
  Swift default `inliers: nil`) counts every sample and is used only by tests.
- New tests in both suites: a 1 s fidget to 10° in the first 1 s and in the last 1 s is accepted
  with an unbiased baseline (while the all-samples drift of the same data is > 3°), and a window
  without inliers (first 0.2 s all outliers, `calibrationDriftWindow` 0.2) fails.
- `./mvnw -B -ntp verify`: **301 JUnit tests, 0 failures**. `rereference --check`: 0 of 14 stale,
  so no reference block was rewritten: no committed fixture has an outlier inside a drift window
  that mattered (the brief-fidget fixture's fidget is at 4 s, and the slow-slouch fixture is still
  rejected because its ramp samples are all inliers).
- Regenerated rows (20 seeds): one 1 s fidget to 10° accepted 20/20 (was 18/20), to 20° 19/20 (was
  18/20). The remaining 20° rejection has the fidget at 8–9 s: the 0.5 s smoothing leaves a decay
  tail whose samples below 5° are inliers and shift the last window by just over 3° (it passes
  with a 4° limit); that residual tilt is real, so the rejection is defensible. Drift table: only
  two cells moved by one run (sway 2° at 4° / 2 s: 3/20, was 4/20; sway 3° at the default:
  10/20, was 11/20); every slouch row is unchanged. Defaults 3° / 2 s still confirmed.
