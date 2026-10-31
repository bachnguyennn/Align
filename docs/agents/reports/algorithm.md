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
