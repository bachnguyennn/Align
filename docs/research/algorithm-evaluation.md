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
3. Calibration: 10 s of smoothed gravity; fails `insufficientSamples` if < 100 samples, and
   (D-017 (b)) `tooMuchMovement` unless at least `calibrationSpreadQuantile` = 90 % of the samples
   are within 5° of the mean; baseline = normalized mean of those inliers (identical to the v1
   mean when every sample is an inlier). D-020: also `tooMuchMovement` if the mean gravity of the
   first 2 s and of the last 2 s (`calibrationDriftWindow`) are more than 3°
   (`calibrationMaxDriftDegrees`) apart, which catches a slow slouch.
3b. Optional guided nod (D-017 (a)): after calibration the user nods once; the forward axis line
   is the principal axis of the head rotation vectors (≥ 3°) in the baseline plane, its sign taken
   from the default axes; lateral = `g0 × forward`. Rejected if more than 45° from the default
   axis or if sideways ÷ forward motion > 0.35. The learned axes are stored on the baseline.
4. Tilt (D-005): minimal rotation `r` taking baseline gravity `g0` to current `g`; head rotation
   = `−r`; forward/lateral = projections on the effective axes (learned, else configured), total
   = angle.
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
leaves second-order crosstalk (0.3° at 10°/−5°, 1.2° at 20°/10°), which neither projection
fixes; axes learned from a guided nod do (D-017, below).

### Decimation (10 seeds; `minimumCalibrationSamples` lowered to 40 for the low rates)

Processing at 25 (no cap), 15, 10 and 5 Hz: all calibrate and detect. The delay beyond the
crossing + 30 s is 0.50, 0.54, 0.54 and 0.64 s. A 10 Hz cap is safe if CPU or battery
requires it, but note that **at 10 Hz the default `minimumCalibrationSamples` = 100 is
borderline**: 10 s gives 100–101 samples. Lower it when capping the rate.

### D-017: guided-nod axis calibration and calibration spread quantile

Java reference, 20 seeds per cell unless noted (full tables in
`analytics/align-tools/results/evaluation.md`).

**(i) Earbud yaw in the ear** (10 seeds; 40 s holds; mean of per-run medians). With the default
axes a yawed earbud reads a forward tilt partly as lateral (≈ 20°·sin yaw) and loses
1 − cos yaw of it; a 16° hold, just above the 15° threshold, is missed from 30° of yaw. After a
guided 25° nod the readings are independent of yaw:

| earbud yaw | default: 20° fwd reads / lateral crosstalk | default: 16° fwd hold reminded | learned: 20° fwd reads / crosstalk | learned: 16° hold reminded |
|---|---|---|---|---|
| 0° | 19.95° / 0.19° | 10/10 | 19.95° / 0.40° | 10/10 |
| 10° | 19.63° / 3.39° | 10/10 | 19.95° / 0.40° | 10/10 |
| 20° | 18.71° / 6.76° | 10/10 | 19.95° / 0.40° | 10/10 |
| 30° | 17.23° / 9.93° | 2/10 | 19.95° / 0.40° | 10/10 |
| 40° | 15.22° / 12.79° | 0/10 | 19.95° / 0.40° | 10/10 |

The lateral direction behaves the same (13.1° forward crosstalk from a 20° side tilt at 40° yaw,
0.36° with learned axes). Noise-free, learned axes give exactly 20.000° / 0.000° even with the
combined 8°/−3° pitch/roll offset that leaves ≈ 1.2° of crosstalk with default axes, so the nod
also removes the second-order mounting error noted below. The 0.40° residual is the sway in the
synthetic hold, not an axis error.

**(ii) Nod success vs sway and amplitude** (earbud yaw 20°; accepted / neutral calibrations that
succeeded, mean |learned yaw − true yaw|):

| sway σ | 8° nod | 12° nod | 20° nod | 30° nod |
|---|---|---|---|---|
| 0.5° | 0/20 | 1/20 | 20/20 (1.0°) | 20/20 (0.7°) |
| 1.0° | 0/20 | 3/20 (2.6°) | 20/20 (2.0°) | 20/20 (1.3°) |
| 2.0° | 1/20 | 7/20 (8.8°) | 20/20 (4.0°) | 20/20 (2.7°) |
| 3.0° | 2/16 | 6/16 (13.3°) | 15/16 (6.2°) | 16/16 (4.3°) |

A nod must clearly exceed the 12° minimum after the 0.5 s smoothing, so the UI should ask for a
deliberate nod of about 20–30°. Small nods that do pass carry large yaw errors at higher sway, so
the 12° minimum is kept (lowering it would accept worse axes). The yaw error grows with sway
because one 2.6 s nod averages little of it: at the default 0.5° sway a 20° nod is within 3° of
the truth (≤ 1° of crosstalk per 20° of tilt). Fit method (ii-b): the principal axis through the
origin (default) beats the sign-aligned sum at every sway (1.00° vs 1.11° at 0.5°, 3.96° vs 4.74°
at 2°); centring the vectors first helps slightly at normal sway (0.86°) but rejects more nods at
high sway (14/20 vs 19/20 at 3°), so it was not adopted.

**(iii) False acceptance** (earbud yaw 0):

| motion during the axis calibration | accepted | inconsistentMotion | noNodDetected |
|---|---|---|---|
| 20° nod (reference) | 20/20 | 0 | 0 |
| diagonal 20° tilt, 30° from forward | 20/20 (learns ≈ 30° yaw) | 0 | 0 |
| diagonal, 45° from forward | 7/20 | 13/20 | 0 |
| diagonal, 60° / ear to shoulder (90°) | 0/20 | 20/20 | 0 |
| circular head roll (forward then sideways) | 0/20 | 20/20 | 0 |
| head turns only, or head turns + 8° nod, or keeping still | 0/20 | 0 | 20/20 |

Head turns never count (heading is excluded by construction). A tilt up to ~40° off the forward
direction is indistinguishable from a yawed earbud and is learned as such: this is the price of
supporting earbud yaw up to 45°, and why the nod must be guided.

**(iv) Neutral calibration spread quantile** (cells: runs with the wanted outcome; measured
before the D-020 drift rule; the current report in `results/evaluation.md` includes the drift
rule, see the next section):

| 10 s calibration | want | q 1.0 (v1) | q 0.95 | **q 0.9** | q 0.8 |
|---|---|---|---|---|---|
| still, sway 2° | accept | 19/20 | 19/20 | 20/20 | 20/20 |
| still, sway 3° | accept | 10/20 | 11/20 | 15/20 | 18/20 |
| one 1 s fidget to 10° | accept | 0/20 | 19/20 | 20/20 | 20/20 |
| one 1 s fidget to 20° | accept | 0/20 | 0/20 | 20/20 | 20/20 |
| nodding ±9°/±4° (fixture motion) | reject | 20/20 | 20/20 | 20/20 | 20/20 |
| two 1.5 s fidgets to 12° | reject | 20/20 | 20/20 | 20/20 | 20/20 |
| looking around ±6° sideways | reject | 20/20 | 20/20 | 18/20 | 7/20 |
| slow slouch 0→10° during the 10 s | reject | 16/20 | 14/20 | 9/20 | 3/20 |

0.9 accepts a single fidget of any size and noisier still users, and still rejects real nodding
and repeated fidgets; 0.8 starts accepting users who look around. Because the baseline is the
inlier mean, an accepted fidget leaves only 0.5° of baseline error (the same as no fidget). The
cost: a slow drift during calibration (slouching 10° over 10 s) is accepted more often than with
the v1 rule (11/20 vs 4/20), leaving a ≈ 4.4° biased baseline; neither rule detects drift well,
which led to the D-020 drift rule below. Gentle ±6° nodding is attenuated to ±4.4° by the
smoothing and accepted by every rule, with a harmless 0.3° baseline error.

### D-020: neutral calibration drift rule

Java reference, 20 seeds per cell. A steady slouch is ramped over the whole 10 s calibration (ten
short eased segments, so the samples spread evenly around the mean, which the spread rule
accepts). Cells: calibrations rejected with `tooMuchMovement`; columns
`calibrationMaxDriftDegrees` / `calibrationDriftWindow`; "no drift rule" is the spread rule alone
(quantile 0.9).

| 10 s neutral calibration | no drift rule | 2° / 2 s | **3° / 2 s (default)** | 4° / 2 s | 3° / 1 s | 3° / 3 s |
|---|---|---|---|---|---|---|
| slouch 0° over the 10 s (sway 0.5°) | 0/20 | 0/20 | 0/20 | 0/20 | 0/20 | 0/20 |
| slouch 3° | 0/20 | 16/20 | 4/20 | 0/20 | 6/20 | 2/20 |
| slouch 5° | 0/20 | 20/20 | 20/20 | 10/20 | 20/20 | 16/20 |
| slouch 10° | 1/20 | 20/20 | 20/20 | 20/20 | 20/20 | 20/20 |
| still, sway 0.5° | 0/20 | 0/20 | 0/20 | 0/20 | 0/20 | 0/20 |
| still, sway 1.0° | 0/20 | 4/20 | 0/20 | 0/20 | 1/20 | 0/20 |
| still, sway 1.5° | 0/20 | 8/20 | 4/20 | 1/20 | 4/20 | 3/20 |
| still, sway 2.0° | 0/20 | 12/20 | 7/20 | 4/20 | 9/20 | 4/20 |
| still, sway 3.0° | 5/20 | 16/20 | 11/20 | 9/20 | 14/20 | 11/20 |

The spread rule alone accepts every steady slouch (19/20 even at 10°, which biases the baseline
by about 5°). The default 3° / 2 s rejects every slouch of 5° or more and none of the still
users at the modelled 0.5° sway or at 1°; a 3° slouch (≈ 1.5° baseline bias) mostly passes,
which is acceptable. The cost is false rejection of very unsteady users: 4/20 at 1.5° sway, 7/20
at 2°, and 11/20 at 3°, where the spread rule already rejects 5/20. Those users are asked to
recalibrate. 3° / 3 s halves the rejections at 2° sway (4/20) but misses 4/20 of the 5°
slouches; 4° / 2 s misses half of them; 2° / 2 s rejects too many still users. **The defaults
3° / 2 s are confirmed**; if real recordings show still users with 1.5–2° of sway, switch to
3° / 3 s. One more side effect: a single 1 s fidget that falls inside the first or last 2 s now
fails the calibration (the fidget rows of the current D-017 (iv) report: 18/20 accepted, was
20/20).

### Throughput

CPython reference: 2551 samples in 38 ms (15 µs/sample). The Java port runs the full evaluation in
about 14 s against 188 s for Python. Informational only.

### Reference ↔ Swift parity

Every fixture in `shared/fixtures/motion` stores the reference output (`reference`; the eight v1
blocks written by the Python reference, the five D-017 blocks by Java). The Java pipeline
reproduces all of them bit for bit (JUnit); D-017 changed none of the v1 blocks. The Swift
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
- Offer the guided nod right after every neutral calibration (each earbud insertion is a new
  fit) and ask for one deliberate nod of about 20–30°, down or up. Keep the D-017 defaults:
  `axisCalibrationMinimumNodDegrees` 12°, `axisCalibrationMaxYawDegrees` 45°,
  `axisCalibrationMaxOffAxisRatio` 0.35, `axisCalibrationDuration` 8 s,
  `calibrationSpreadQuantile` 0.9, and (D-020) `calibrationMaxDriftDegrees` 3° with
  `calibrationDriftWindow` 2 s (tables above). On a calibration `tooMuchMovement` the UI should
  say "hold still and upright for 10 s", which covers both a fidgety and a slouching user. On `.inconsistentMotion` ask the user to nod
  straight down; on `.noNodDetected` to nod further.
- Record real AirPods sessions (D-017 (d); `exec:java@replay`, format in
  `shared/fixtures/README.md`) before tuning further; the first things to check are the learned
  yaw spread across insertions and the sway level during calibration and the nod.

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
- **Axis convention is unverified (D-011).** The guided nod removes the dependence on it for
  users who do the nod: the axis line is learned per fit, and only its sign comes from the
  default (a nod down or up gives the same axes). Without the nod, a wrong sign flips
  forward/backward or left/right; the fix is configuration only (`PostureConfiguration.axes`).
  If the default forward axis were swapped with the lateral one, every correct nod would be
  rejected as more than 45° off; S-05 must still confirm the default.
- **The user may nod wrongly.** A diagonal tilt up to ~40° from forward is accepted and learned
  as earbud yaw; small nods (< ~15° after smoothing) are rejected; with large sway (≥ 2°) one
  nod gives yaw errors of 4–6° on average (up to 12–18°). The nod must be guided by the UI.
- **Calibration drift detection trades off against unsteady users (D-020).** Slouches of 5° or
  more during the calibration are now rejected, but still users with 1.5–3° of sway are
  rejected 4/20 to 11/20 times and must recalibrate; a slouch of about 3° passes and biases the
  baseline by about 1.5°. Both depend on the sway level of real users, which is unknown until
  recordings exist.
- **Earbud hand-off (`sensorLocation` changes) is not treated as an interrupt.** Samples are
  processed as continuous data. An interrupt would split episodes and delay reminders without
  fixing the real risk: the two earbuds may sit at different angles, and the baseline and the
  learned axes belong to one earbud's fit. If S-05 shows a gravity step at hand-off, the better
  fix is a per-earbud baseline (and axes).
- **Direction is locked at onset.** A forward tilt that turns into a lateral tilt keeps
  reporting `forward` until forward falls below its release level.
- **No activity gating.** Walking, conversation nods and lying down are not recognized; lying
  on the back reads as a large backward tilt. Monitoring assumes a seated user.
- **No watchdog in the pipeline.** If samples simply stop, the pipeline cannot notice without a
  new sample; the app must call `interrupt(at:)` on disconnect or pause (D-017 (c) adds an app
  watchdog).
