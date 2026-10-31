# Algorithm evaluation: sustained head-tilt detection

Owner: Algorithm agent. Status: evaluated on **synthetic data only** (no hardware recordings
yet). Task A-04.

## Reproduce

```sh
cd analytics/align-tools
./mvnw verify                                                        # JUnit, incl. fixture replay
./mvnw -q compile exec:java@evaluate -Dexec.args="--seeds 20"        # ~15 s; writes results/evaluation.md
```

All numbers below were produced by the original Python reference (numpy 2.5.4, CPython 3.12,
Windows 11; `analytics/experiments/results/evaluation.md`, removed after the Java port (D-015) and
still in git history). The Java report (`analytics/align-tools/results/evaluation.md`) reproduces
the noise-free axis-projection table exactly; every other table uses the Java generator's random
streams and differs only within noise, with the same conclusions.

## Method

**Pipeline under test** — the reference pipeline (originally Python, now `analytics/align-tools`
in Java with identical output; the executable specification). The Swift `PostureDetection` module
mirrors it line for line:

1. Gap check (gap > `maxSampleGap` = 1 s ⇒ interrupt at the previous sample) and optional
   decimation (`maxProcessingRateHz`).
2. Smoothing of the head-frame unit gravity vector: EMA with `alpha = 1 − exp(−dt/τ)`,
   renormalized (τ = `smoothingTimeConstant` = 0.5 s). Time-based, so rate- and jitter-independent.
3. Calibration: 10 s of smoothed gravity; baseline = normalized mean; fails `tooMuchMovement` if
   any sample is > 5° from the mean, `insufficientSamples` if < 100 samples.
4. Tilt (D-005): minimal rotation `r` taking baseline gravity `g0` to current `g`; head rotation
   = `−r`; forward/lateral = projections on the configured axes, total = angle.
5. State machine: neutral → deviating (component ≥ threshold; direction = largest
   |angle|/threshold ratio, then locked) → sustainedTilt after 30 s → neutral once the component
   drops below threshold − hysteresis (3°). Episodes are emitted when a sustained tilt ends or on
   interrupt.
6. Reminders: on the update a tilt becomes sustained, if ≥ `reminderCooldown` (300 s) since the
   last reminder; at most one per episode.

**Sign derivation.** Let `R0` be the head-to-world attitude at neutral and `R1 = R0·D` now, with
`D` the head's rotation in the head frame. With world gravity `gw = (0,0,−1)` (Core Motion's
Z-vertical reference), head-frame gravity is `g0 = R0ᵀgw` and `g = R1ᵀgw = Dᵀg0`. The rotation
taking `g0` to `g` is `D⁻¹`: gravity seen in the head frame turns opposite to the head, so the
head rotation vector is `−r`. Rotation about `g0` (heading) leaves `g` unchanged and is excluded.
Checked numerically (JUnit `signDerivationForwardRotationGivesPositiveForward`, and
the Swift test of the same name): a +20° rotation about `forwardAxis` gives `r = −20°·forwardAxis`
and `forwardDegrees = +20.000000000`.

**Axis convention (D-011).** Head frame +X right ear, +Y nose, +Z up; `forwardAxis = (−1,0,0)`,
`lateralAxis = (0,1,0)`; `forwardAxis × lateralAxis = (0,0,−1)`. Cross-checks asserted in both
test suites: +20° chin-down ⇒ head-frame gravity `(0, +0.342, −0.940)`; +20° right-ear-down ⇒
`(+0.342, 0, −0.940)`. **Unverified on hardware (S-05).** The code never hard-codes axes; it
reads `PostureConfiguration.axes`.

**Baseline-plane axes (refinement within D-005).** `r` is always perpendicular to `g0`. Before
projecting, each configured axis is projected onto the plane perpendicular to `g0` and
renormalized. When the axes are already perpendicular to `g0` this is identical to the plain dot
product; when the earbud sits pitched or rolled in the ear it removes the `cos(offset)`
under-reading (see the table below).

**Synthetic data** — the fixture generator (`Generator.java`, ported from `generator.py`): scripted pose (cosine-eased keyframes and
glances) + OU sway (σ 0.5°, τ 1.5 s) + 0.25 Hz breathing + Poisson micro-movements (N(0, 1.5°),
≤ 4°, 0.6–2 s, none during calibration) + heading random walk and 15–45° head turns + earbud
mounting offset (pitch 8°, roll −3°) + 0.05° white sensor noise + 4 ms timestamp jitter, at
25 Hz (some fixtures at 20 Hz). Ground truth is the noise-free scripted pose; an episode "should"
start when the true component reaches the threshold.

**Metrics.** Detection latency (reminder time minus tilt onset and minus the truth threshold
crossing); false reminders and false episodes on neutral and glance scenarios; flicker
(entries into `deviating`); fragmentation (number of sustained episodes for one held posture);
calibration success under sway; axis-projection error under mounting offsets.

## Results

### Detection latency (default configuration, 20 seeds each)

| scenario | exactly 1 reminder | reminder − tilt onset (s) | reminder − truth threshold crossing (s) | delay beyond `sustainedDuration` (s) |
|---|---|---|---|---|
| gradual forward slouch (0→24° over 10 s) | 20/20 | 36.27 (35.96–36.60) | 30.47 (30.16–30.80) | 0.47 (0.16–0.80) |
| lateral right tilt (0→20° over 3 s) | 20/20 | 32.55 (32.48–32.64) | 30.55 (30.47–30.64) | 0.55 (0.47–0.64) |
| looking up (0→−30° over 3 s) | 20/20 | 32.36 (32.24–32.48) | 30.53 (30.41–30.66) | 0.53 (0.41–0.66) |

Latency is the 30 s `sustainedDuration` (a product decision) plus about 0.5 s of filter lag (τ).
For a step from 0 to 25° the lag is exactly τ·ln(25/10) = 0.46 s, which a unit test asserts.

### False positives and flicker (20 seeds each)

| scenario | monitored minutes | reminders | episodes | entries into `deviating` per minute |
|---|---|---|---|---|
| steady neutral (sway, micro-movements, head turns) | 15.0 | **0** | **0** | 0.00 |
| brief glances down (3–5 s to 26–34°, every 9–15 s) | 20.7 | **0** | **0** | 4.65 (3.87–4.84) |

Glances correctly enter `deviating` (one entry per glance) but never become sustained. Glance
length that triggers a reminder (30° glance, 20 seeds each): 5, 10, 20 and 29 s ⇒ 0/20; 31, 32
and 40 s ⇒ 20/20. The boundary is exactly `sustainedDuration` plus the ramps.

### Flicker near the threshold: hysteresis × smoothing (10 seeds, 60 s hold, forward threshold 15°)

Mean entries into `deviating` per 60 s hold / mean number of sustained episodes:

| hysteresis | τ | hold at 14° | hold at 15° | hold at 16° |
|---|---|---|---|---|
| 0° | 0 s | 11.6 / 0.0 | 55.0 / 0.0 | 16.2 / 0.2 |
| 0° | 0.5 s | 1.8 / 0.0 | 11.5 / 0.0 | 3.4 / 0.7 |
| 1° | 0.5 s | 1.6 / 0.0 | 2.2 / 0.6 | 1.3 / 1.0 |
| **3° (default)** | **0.5 s** | **0.8 / 0.4** | **1.0 / 1.0** | **1.0 / 1.0** |
| 3° | 2.0 s | 0.2 / 0.1 | 0.9 / 0.9 | 1.0 / 1.0 |
| 5° | 0.5 s | 0.8 / 0.4 | 1.0 / 1.0 | 1.0 / 1.0 |

Without hysteresis, a posture held at the threshold flickers up to 66 times a minute and never
accumulates 30 s, so the user is never reminded. With the default 3° the held posture produces
exactly one deviation and one episode. Hysteresis also latches: once noise pushes a 14° hold over
15°, it stays engaged until the tilt drops below 12°, so 40% of 14° holds became episodes. That
is acceptable (the user is within 1° of the threshold), but it means the effective threshold for
a sustained hold is "touch 15°, then stay above 12°". Full grid in `results/evaluation.md`.

### Threshold sensitivity (10 seeds, 45 s hold)

| forward threshold | hold 12° | hold 15° | hold 18° | hold 20° | hold 25° | reminders on noisy neutral (sway 1°, micro every 4 s) |
|---|---|---|---|---|---|---|
| 10° | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | 0 |
| 12° | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | 0 |
| 15° (default) | 0/10 | 10/10 | 10/10 | 10/10 | 10/10 | 0 |
| 18° | 0/10 | 0/10 | 10/10 | 10/10 | 10/10 | 0 |
| 20° | 0/10 | 0/10 | 2/10 | 10/10 | 10/10 | 0 |

Under the modelled noise, a hold at or above the threshold is detected and a hold 3° below is
not. Even a 10° threshold produces no reminders on a noisier neutral. Thresholds below 10° were
not evaluated.

### Smoothing time constant (20 seeds)

| τ | slouch detected | delay beyond crossing + 30 s | deviating entries, glance scenario |
|---|---|---|---|
| 0 s | 20/20 | 0.01 s (−0.41–0.39) | 4.8 |
| 0.25 s | 20/20 | 0.25 s | 4.8 |
| **0.5 s** | 20/20 | **0.50 s** (0.15–0.88) | 4.8 |
| 1.0 s | 20/20 | 1.02 s | 4.8 |
| 2.0 s | 20/20 | 1.97 s | 4.8 |

τ adds about τ seconds of latency and does not change glance handling, which comes from the
duration rule. Its value is reducing flicker near the threshold (table above). 0.5 s is a good
compromise.

### Calibration robustness (20 seeds)

Sway σ during the 10 s calibration of 0.5°, 1.0°, 1.5° and 2.0° ⇒ 20/20 succeed; 3.0° ⇒ 13/20.
The deliberate ±9°/±4° movement in the `calibration_too_much_movement` fixture fails with
`tooMuchMovement` as intended.

### Axis projection under earbud mounting offset (noise-free 20° poses, error in degrees)

| mount pitch/roll | baseline-plane: forward err | lateral err | lateral→forward crosstalk | plain projection: forward err | lateral err |
|---|---|---|---|---|---|
| 0/0 | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |
| 10°/0 | 0.000 | 0.000 | 0.000 | 0.000 | −0.304 |
| 20°/0 | 0.000 | 0.000 | 0.000 | 0.000 | −1.206 |
| 0/10° | 0.000 | 0.000 | 0.000 | −0.304 | 0.000 |
| 10°/−5° | −0.002 | 0.000 | −0.304 | −0.076 | −0.304 |
| 20°/10° | −0.036 | 0.000 | 1.204 | −0.304 | −1.206 |

Baseline-plane axes remove the single-axis offset error exactly. A combined pitch+roll offset
leaves second-order crosstalk (0.3° at 10°/−5°, 1.2° at 20°/10°), which neither method fixes.

### Decimation (10 seeds; `minimumCalibrationSamples` lowered to 40 for the low rates)

Processing at 25 (no cap), 15, 10 and 5 Hz: all calibrate and detect. The delay beyond the
crossing + 30 s is 0.50, 0.54, 0.54 and 0.64 s. A 10 Hz cap is safe if CPU or battery
requires it, but note that **at 10 Hz the default `minimumCalibrationSamples` = 100 is
borderline**: 10 s gives 100–101 samples. Lower it when capping the rate.

### Throughput

CPython reference: 2551 samples in 38 ms (15 µs/sample). The Java port runs the full evaluation in
about 14 s against 188 s for Python. Informational only.

### Reference ↔ Swift parity

Every fixture in `shared/fixtures/motion` stores the reference output (`reference`, written by
the Python reference). The Java port reproduces all eight blocks bit for bit (JUnit). The Swift
`FixtureReplayTests` assert the same reminder/episode counts, directions, calibration outcomes,
final state and number of state transitions, with times within one sample period and degrees
within 0.05°; they pass in CI (`swift-package` and `swift-linux`).

## Recommendations

- Keep the defaults: thresholds 15°/20°/15°, hysteresis 3°, τ 0.5 s, sustained 30 s, cooldown
  300 s. On synthetic data they give no false reminders, about 0.5 s added latency and stable
  states near the threshold.
- Sensitivity presets for the UI (thresholds only; keep hysteresis 3° and τ 0.5 s):
  **Relaxed** 20° / backward 25° / lateral 20°, sustained 60 s; **Standard** = defaults;
  **Strict** 12° / backward 18° / lateral 12°, sustained 20 s. Reminder frequency is a separate
  setting (cooldown 2 / 5 / 10 min).
- Record real AirPods sessions during S-05 and add them as fixtures before tuning further.

## Head tilt vs. forward head translation

AirPods Pro report the **orientation** of the earbuds (an attitude quaternion and the gravity
direction in the earbud frame), not their position. Align's tilt estimate therefore measures
**head rotation**: flexion (chin toward chest), extension (looking up) and lateral bending,
relative to a calibrated neutral orientation.

"Forward head posture" in the clinical and ergonomic sense is largely a **translation**: the
head moves forward of the shoulders. It is typically assessed with the craniovertebral angle
between the C7–tragus line and the horizontal. It combines lower-cervical flexion with
upper-cervical extension, so the head can protrude by centimetres while its orientation (where
the face points) barely changes. The reverse also happens: nodding down at a phone with the neck
otherwise stacked over the shoulders is large head flexion with little protrusion.

A head-worn IMU cannot directly observe that translation:
- Gravity direction only encodes orientation; a pure translation leaves it unchanged.
- Position from the accelerometer needs double integration of user acceleration, which drifts
  by metres within seconds and is useless for postural drift over minutes.
- There is no torso reference. Without a second sensor on the trunk, the head's position
  relative to the shoulders is unobservable.

Sustained head flexion and forward head translation often co-occur (looking down at a laptop or
phone tends to produce both), so tilt is a plausible **proxy**. It is not a measurement of
forward head posture: it will miss protrusion without flexion and flag flexion without
protrusion.

**Align's claim is therefore limited to: "notices sustained head tilt (forward/backward
flexion and side-bending) relative to your calibrated neutral position."** It must not claim to
measure or correct forward head posture, craniovertebral angle or spinal alignment, and it is a
wellness tool, not a medical device. UI copy should say "your head has been tilted forward for a
while", not "forward head posture detected".

## Limitations and open questions

- **All results are synthetic.** The motion model is plausible but not fitted to real AirPods
  data. Real sessions may show more drift, sensor-fusion transients or different noise.
- **Axis convention is unverified (D-011).** A wrong sign flips forward/backward or left/right;
  a swapped axis mixes them. The fix is configuration only (`PostureConfiguration.axes`).
- **Earbud yaw in the ear, and combined pitch+roll, are not compensated** (up to about 1.2°
  crosstalk per 20° tilt in the cases above). A short guided nod during calibration could learn
  the flexion axis; not implemented.
- **Earbud hand-off (`sensorLocation` changes) is not treated as an interrupt.** Samples are
  processed as continuous data. An interrupt would split episodes and delay reminders without
  fixing the real risk: the two earbuds may sit at different angles. If S-05 shows a gravity step
  at hand-off, the better fix is a per-earbud baseline offset.
- **Reminders are decided only at the moment a tilt becomes sustained** (contract §2). An episode
  that becomes sustained inside the cooldown never reminds, even if it lasts long after the
  cooldown ends (proposal in `docs/agents/reports/algorithm.md`).
- **Direction is locked at onset.** A forward tilt that turns into a lateral tilt keeps
  reporting `forward` until forward falls below its release level.
- **No activity gating.** Walking, conversation nods and lying down are not recognized; lying
  on the back reads as a large backward tilt. Monitoring assumes a seated user.
- **No watchdog.** If samples simply stop, the pipeline cannot notice without a new sample; the
  app must call `interrupt(at:)` on disconnect or pause.
