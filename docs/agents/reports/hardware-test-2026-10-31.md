# Hardware test: iPhone 17, AirPods (2026-10-31)

First run of [`TESTING.md`](../../../TESTING.md) on real hardware, plus the automated suites from
[`test-plan.md`](../test-plan.md). Values are what the tester read off the Diagnostics screen;
anything not recorded is marked as such.

## Setup

| Field | Value |
|---|---|
| Date | 2026-10-31 |
| App commit | `7295ecb` |
| Build | Debug, Xcode 27.1 (27A9275), signed with a free Personal Team, installed with `devicectl` |
| iPhone model / iOS | iPhone 17 (iPhone18,3), iOS 27.0.1 (24A446) |
| AirPods model / firmware | not recorded |
| Sample rate / largest gap | not recorded |

## Automated suites (local Mac)

| Suite | Result |
|---|---|
| Hygiene: CRLF, no tracked `.xcodeproj`, shellcheck | Pass |
| Java `./mvnw -B -ntp verify` (`analytics/align-tools`, JDK 23) | Pass, 177 tests, 0 failures |
| Swift `swift test` (`ios/AlignKit`) | Pass, 127 tests (AlignCore 42, PostureDetection 52, Sensors 33) |
| `AlignKit-Package` build for generic iOS Simulator | Build succeeded |
| App `xcodebuild build` + `test` (iPhone 17 simulator, iOS 26.5) | Pass, 32 tests, 0 failures |

Local toolchain differs from CI (Xcode 27.1 vs 16.4, JDK 23 vs 21).

## Axis check (T-01, S-05)

Upright gravity (g): `-0.058 +0.362 -0.931`. The z axis carries gravity when upright; x ≈ 0
(no roll); the y component is a ~21° front-back offset, which calibration absorbs.

| Move | Expected | Saw | Streaming earbud |
|---|---|---|---|
| Chin down | Forward + | F +58, L −1.6 | not recorded |
| Look up | Forward − | F −76, L +5 | not recorded |
| Right ear down | Lateral + | F −4, L +23 | right |
| Left ear down | Lateral − | F +37, L −50 | **left** |
| Turn left | both ≈ 0 | F −19, L −11 | right |
| Turn right | both ≈ 0 | F −18, L +3 | right |

Final row set taken after recapturing neutral before each move and reading only the Axis check
section. **Signs match `HeadAxisConvention.airPodsDefault` (D-011) on both axes**, so no axis
change is needed. Earlier, uncontrolled tries of left ear down gave F −11 / L −14 and
F −32 / L +47 (see finding 2).

## Calibration and reminders

| Step | Expected | Saw |
|---|---|---|
| Calibrate (C-01) | Succeeds after ~10 s | Failed repeatedly with "moved too much"; succeeded with the phone held at eye level (finding 1) |
| Glance down, repeated (T-03) | No reminder | Observed: one reminder in total over the whole run |
| Hold forward tilt 45 s (T-04) | One reminder ~30 s after crossing | One reminder; seconds not timed |
| Keep holding (T-05) | No second reminder | No second reminder reported |
| Sit back up (T-06) | Neutral; History shows one forward tilt | History not checked |
| Right ear down 45 s (T-10) | One right reminder | Not confirmed |

## Disconnects and leaving the app

Not run yet (R-01…R-05, N-03, N-04).

## Findings

1. **Calibration has no settle period.** `CalibrationService` starts collecting on the first
   sample after **Start calibration** is tapped and fails if any sample is more than
   `calibrationMaxSpreadDegrees` (5°) from the mean. The user is looking down at the phone when
   tapping, so raising the head to look ahead fails every attempt. Workaround: hold the phone at
   eye level. Proposed fix: a short countdown (~3 s) before samples are collected, mirrored in
   the Java reference.
2. **Readings look inconsistent while the left earbud streams.** The only cross-axis leakage
   (F +37 on a lateral tilt) and both inconsistent left-tilt tries happened on the left side, and
   in the controlled run the stream had switched to the left bud while neutral was most likely
   captured on the right one. Hypothesis, not verified: the two buds report gravity in slightly
   different frames, so values jump when `sensorLocation` changes. Next step: capture neutral,
   then log gravity across a forced bud switch (R-01: take the streaming bud out).
3. **Head turns move Forward by about −19°** on both sides (T-02 expects under ~5°). Possibly the
   tester's head tipped up while turning. Below the 20° backward threshold, so not expected to
   cause reminders on its own; recheck while watching for pitch.

## Still to do

- AirPods model/firmware, sample rate and largest gap.
- Time from crossing to reminder; History check; lateral reminder.
- Disconnect and app-lifecycle table.
