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
