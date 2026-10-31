# Align — Test plan

Owner: QA agent (task Q-03). Version: v1, written before the app exists.

Status words follow `task-board.md`. A case is **Pass** only when it actually ran with the result
recorded below. Anything about iOS or AirPods behavior that has not been observed on hardware is
marked *to verify*, not assumed.

Defaults referenced below come from `PostureConfiguration.default` (AlignCore, v1): calibration
10 s, forward threshold 15°, backward 20°, lateral 15°, hysteresis 3°, sustained duration 30 s,
reminder cooldown 300 s, max sample gap 1 s. If the defaults change, update the timings here.

## 1. Test strategy matrix

| Level | What it covers | Where it runs | Owner | Blocking? |
|---|---|---|---|---|
| **Unit — AlignCore** | Vector/quaternion math, Codable shapes and persisted raw values, default-config consistency (`Tests/AlignCoreTests`) | CI `swift-package` (macOS), `swift-linux` | QA | Yes (macOS); Linux non-blocking for now |
| **Unit — PostureDetection** | `MotionFilter`, `CalibrationService`, `PostureDetector`, `ReminderDecisionEngine`, `PostureMonitor` state machine: thresholds, hysteresis, sustained duration, cooldown, direction precedence, `maxSampleGap` and `interrupt` | CI `swift-package`, `swift-linux` | Algorithm | Yes |
| **Unit — Sensors** | `MockSensorProvider` event order (first event is `.connectionChanged`, `stop()` emits `.idle` and finishes), every scenario, `gravity` always set, mock tilt sign matches `TiltEstimate`; `SampleRateMeter` | CI `swift-package`, `swift-linux` | Sensor | Yes |
| **iOS compile of package** | `#if os(iOS)` code (`RealAirPodsSensorProvider`) compiles against the iOS SDK | CI `swift-package` (generic iOS Simulator build) | Sensor | Yes |
| **Fixture replay** | The same `shared/fixtures/motion/*.json` files replayed by Python (`analytics/experiments`) and Swift (`PostureDetectionTests`) produce the same reminders and episodes | CI `python` + `swift-package` | Algorithm | Yes, once A-03 lands |
| **App unit** | `MonitoringController` driven by `MockSensorProvider`; session lifecycle and pause; SwiftData with an in-memory container (session/event writes, cascade delete, delete-all); monotonic timestamp → `Date` conversion; daily summaries incl. a session crossing midnight; reminder delivery through a fake notification center; settings JSON round trip | CI `ios-app` (iOS Simulator) | Frontend | Yes |
| **Simulator, mock sensor** | Manual walkthrough of every screen with demo mode; each `MockScenario`; unavailable/permission states; accessibility | Developer Mac / Xcode Simulator | Frontend + QA | Release checklist |
| **Physical device** | Real Core Motion stream, axis signs (S-05), permissions, disconnects, notifications, background behavior, battery, offline | iPhone + AirPods Pro, run by the user | User + QA | Release checklist; S-05 blocks trusting default axes |

### CI jobs (`.github/workflows/ci.yml`)

| Job | Runner | Runs | Skips cleanly when |
|---|---|---|---|
| `hygiene` | ubuntu-24.04 | CRLF check, generated `.xcodeproj` not tracked, shellcheck | — |
| `python` | ubuntu-24.04, Python 3.12 | `pip install -r analytics/requirements.txt`, `pytest analytics/experiments` | `analytics/experiments` absent |
| `java` | ubuntu-24.04, Temurin 21 (`setup-java`, Maven cache) | `./mvnw -B -ntp verify` in `analytics/align-tools` (JUnit: pipeline, fixture replay + Python parity, generator, evaluation); test count as a notice | — |
| `swift-package` | macos-15, Xcode 16.4 | `swift build --build-tests`, `swift test`, iOS Simulator build of `AlignKit-Package` | — |
| `swift-linux` | `swift:5.10-jammy` container | `swift build --build-tests`, `swift test` (`continue-on-error`) | — |
| `ios-app` | macos-15, Xcode 16.4 | `xcodegen generate`, `xcodebuild build`, `xcodebuild test` on the newest available iPhone simulator | `ios/project.yml` absent |

Read results without logging in: `scripts/ci-status.sh [branch]`.

### Simulator mock walkthrough (one pass per release candidate)

| ID | Scenario (demo mode) | Expected | Result |
|---|---|---|---|
| SIM-01 | Fresh install on simulator, no demo mode | Onboarding explains AirPods requirement; sensor state shows motion not supported (`.unavailable(.motionNotSupported)`), offers demo mode; no crash | |
| SIM-02 | `steadyNeutral` | Calibration succeeds; state stays neutral; no reminders | |
| SIM-03 | `gradualForwardSlouch` | Deviating, then sustained tilt about 30 s after crossing 15°; exactly one reminder; one forward episode stored after return | |
| SIM-04 | `briefGlanceDown` | Deviating flashes only; no reminder; no stored episode | |
| SIM-05 | `lateralTilt` (≈20° right, 45 s) | One `right` reminder; one `right` episode | |
| SIM-06 | `disconnectMidSession` | Disconnected state shown within 1 s of the gap; open episode closed; monitoring resumes on reconnect without recalibrating | |
| SIM-07 | `unavailable` / `permissionDenied` | Correct explanation and recovery path (Settings deep link for denied) | |
| SIM-08 | `manual` with the tilt slider | Orientation indicator follows sign conventions (forward = chin down, right = right ear down) | |
| SIM-09 | Accessibility: Dynamic Type XXXL, VoiceOver, dark mode, reduced motion | All controls reachable and labeled; no clipped text | |
| SIM-10 | Privacy & Data → delete all | Sessions, events and baseline gone; app returns to needs-calibration | |

## 2. Physical device protocol (iPhone + AirPods Pro)

### 2.1 Record the environment first

| Field | Value |
|---|---|
| Date / tester | |
| App commit SHA (Settings → About, or `git rev-parse HEAD`) | |
| Build type (Debug from Xcode / TestFlight) | |
| iPhone model, iOS version | |
| AirPods model and firmware (Settings → [AirPods] → About) | |
| Non-motion headphones used for D-03 | |
| Other Bluetooth audio devices nearby (Mac, iPad on same Apple ID) | |

Preparation:

1. Install the build. For permission tests, delete the app first so the motion prompt appears again.
2. Turn off automatic AirPods switching to other devices for the duration (Settings → [AirPods] →
   Connect to This iPhone → When Last Connected to This iPhone), or sign the Mac/iPad out of
   Bluetooth range; otherwise a Mac can take the AirPods mid-test.
3. Keep a stopwatch running; note wall-clock times in the Notes column. The Diagnostics screen
   (F-02) should show connection state, sample rate and largest gap.
4. Sit upright, phone on a stand, screen on unless the case says otherwise.

Result column: **Pass**, **Fail** (describe), or **Observed** (for behavior we document rather
than require). Record numbers (seconds, %, Hz) wherever the expected result has one.

### 2.2 Permissions and availability

| ID | Steps | Expected | Result | Notes |
|---|---|---|---|---|
| D-01 | Fresh install, AirPods in ears. Start monitoring (or open Diagnostics). | System prompt for Motion & Fitness appears with the `NSMotionUsageDescription` text. Text is plain, says data stays on the device. | | |
| D-02 | Tap **Allow**. | State becomes connected; samples stream; Diagnostics shows a sample rate (record Hz; reported ≈25 Hz, *to verify*) and `gravity` values. | | |
| D-03 | Delete and reinstall. At the prompt tap **Don't Allow**. | State `.unavailable(.notAuthorized)`; app explains how to enable it and offers a button that opens Settings; no crash, no repeated prompt loop. Demo mode still available. | | |
| D-04 | Settings → Privacy & Security → Motion & Fitness → Align **on**, return to app. | App detects the change on foreground (or after tapping retry) and streams without reinstall. | | |
| D-05 | Settings → Privacy & Security → Motion & Fitness → **Fitness Tracking off** (global). | Record the authorization status reported (`restricted` or `denied`, *observe*); app shows the not-authorized state. Turn it back on afterwards. | | |
| D-06 | Connect headphones without head tracking (e.g. AirPods 2nd gen, EarPods via adapter, generic Bluetooth). Start monitoring. | No samples. Expected app state: waiting for compatible headphones (on a real iPhone `isDeviceMotionAvailable` describes the phone, not the headphones, so `.unavailable(.motionNotSupported)` is not expected here; *to verify*). Message names the supported models. No crash. | | |
| D-07 | No headphones connected at all. Start monitoring. | Waiting-for-headphones state; starts streaming within a few seconds after AirPods are put in. | | |

### 2.3 Calibration

| ID | Steps | Expected | Result | Notes |
|---|---|---|---|---|
| C-01 | Sit upright, look straight ahead, start calibration, keep still for 10 s. | Progress 0→100% over ≈10 s; success; baseline version 1 (2, 3… on repeats). Record the duration. | | |
| C-02 | Start calibration and nod / turn the head repeatedly. | Fails with "too much movement"; previous baseline (if any) kept; retry offered. | | |
| C-03 | Start calibration, remove both earbuds at ~5 s. | Fails with sensor interrupted; no baseline saved; clear message. | | |
| C-04 | Calibrate, kill the app, relaunch, start monitoring. | Stored baseline reused (no recalibration needed); tilt near 0° when upright. | | |
| C-05 | Calibrate while looking at a phone held at chest height (deliberately bad neutral). | Observed: app accepts it (we cannot know true neutral). Check the app tells the user to calibrate upright. | | |

### 2.4 Detection, reminders and cooldown

Use a fresh calibration (C-01) and the default configuration. Every case that expects a
reminder needs ≥ 5 min since the previous reminder (cooldown), except T-07 which tests exactly
that. To save time, run the non-cooldown cases (T-01…T-06, T-09…T-12) in a debug build with a
shorter cooldown, but run T-07/T-08 with the default and record which configuration was used.

| ID | Steps | Expected | Result | Notes |
|---|---|---|---|---|
| T-01 | Axis check (S-05): tilt chin to chest ~20°, hold 5 s; look up ~20°; right ear to right shoulder ~20°; left ear to left shoulder. | Live forward ≈ +20 / backward ≈ −20 / lateral ≈ +20 / ≈ −20. If any sign or axis is wrong, record it: `HeadAxisConvention.airPodsDefault` (D-011: forward (−1,0,0), lateral (0,1,0), unverified) must change. Also record raw `gravity` when upright (which axis reads ≈ −1 g). | | |
| T-02 | Turn the head left and right (heading only), ±60°. | Forward and lateral tilt stay under ~5°; no deviation. | | |
| T-03 | Glance: look down ~30° for 3–5 s, back up; repeat 5 times over 1 min. | Deviating state appears briefly; **no** reminder; **no** stored episode. | | |
| T-04 | Sustained: tilt forward ~25° and hold 45 s. | Deviating on crossing 15°; sustained ≈30 s later (+ smoothing lag, < 2 s); exactly one reminder (haptic/notification). Record the time from crossing to reminder. | | |
| T-05 | Continue T-04: keep holding for 2 more minutes. | No second reminder in the same episode. | | |
| T-06 | Return upright. | Back to neutral once below 12° (threshold − hysteresis); a forward episode is stored with duration and peak ≈25°, reminder = yes. | | |
| T-07 | Within 5 min of T-04's reminder, hold another 25° tilt for 45 s. | Sustained state, **no** reminder (cooldown 300 s); episode stored with reminder = no. | | |
| T-08 | After ≥ 5 min since the last reminder, hold a tilt for 45 s. | Reminder fires again. Record time since previous reminder. | | |
| T-09 | Hover around the threshold (~14–16°) for 60 s. | No rapid flapping between neutral and deviating (hysteresis); at most one episode. | | |
| T-10 | Lateral: right ear down ~20° for 45 s. | One `right` reminder; episode direction `right`. Repeat for `left`. | | |
| T-11 | Walk around the room for 2 min with normal posture. | No reminders. Record any false positives. | | |
| T-12 | Look up ~25° (backward) for 45 s (respect the cooldown: wait 5 min after the last reminder). | One `backward` reminder ≈30 s after crossing 20° (backward threshold). Then look up only ~15° for 45 s: no reminder. Note whether backward reminders feel useful (product question). | | |

### 2.5 Disconnects and reconnects

Start a monitoring session and hold neutral unless noted.

| ID | Steps | Expected | Result | Notes |
|---|---|---|---|---|
| R-01 | Remove one earbud. | *Observe*: does the stream continue from the other bud (`sensorLocation` changes) or stop? Record. App must not crash or show stale tilt. | | |
| R-02 | Remove both earbuds (automatic ear detection on). | Within ~1 s (max sample gap) state shows disconnected / waiting; live tilt hidden; session paused, not counted as monitored time. | | |
| R-03 | During a sustained tilt (after reminder), remove both earbuds. | Open episode closed at the last sample and stored once; no extra reminder. | | |
| R-04 | Put both earbuds in the case and close the lid. | Disconnected state; no crash; no error loop. | | |
| R-05 | Take them out and put them in again. | Reconnects automatically; monitoring resumes without recalibration; record the reconnect time. | | |
| R-06 | Bluetooth off from **Settings → Bluetooth** (full off). | Disconnected state; message suggests turning Bluetooth on. | | |
| R-07 | Bluetooth off from **Control Center** (only disconnects accessories). | Same as R-06; *observe* whether reconnect is automatic after toggling back. | | |
| R-08 | Turn Bluetooth back on. | Reconnects and resumes as R-05. | | |
| R-09 | Let a Mac/iPad on the same Apple ID take the AirPods (play audio there), then return them. | Disconnect handled as R-02; resumes when AirPods return. | | |
| R-10 | Phone call or Siri during monitoring. | *Observe* whether motion continues; no crash; state correct afterwards. | | |
| R-11 | Monitoring with automatic ear detection **off**, remove both earbuds. | *Observe* (the stream may continue with buds on the desk); document what the user sees. | | |

### 2.6 Notifications and app lifecycle

Notification permission must be granted first (and also test D-03-style denial for notifications).

| ID | Steps | Expected | Result | Notes |
|---|---|---|---|---|
| N-01 | Notification permission prompt: deny. Trigger a sustained tilt in foreground. | In-app banner + haptic still work; app explains how to enable notifications; no crash. | | |
| N-02 | Allow notifications. App in foreground, trigger T-04. | Reminder shown in-app (or as a banner if the app opts in via `willPresent`); haptic plays if enabled; sound respects the setting and the silent switch. | | |
| N-03 | Start monitoring, press Home / swipe up (app backgrounded, screen on), hold a tilt for 60 s. | MVP is foreground-only (D-010, no `UIBackgroundModes`). Expected: monitoring pauses on backgrounding; no reminder; the paused time is not counted as monitored. **Observe and record** what actually happens (does the stream stop at once, after a few seconds, or keep delivering?). | | |
| N-04 | As N-03 but lock the phone. | Expected: monitoring pauses (D-010). **Observe and record** whether any samples arrive while locked and how fast monitoring resumes after unlock + return to the app. | | |
| N-05 | Background the app for 10 min, then return. | Session resumes (or asks to resume, as designed) without recalibration; monitored time excludes the 10 min; an episode open at backgrounding was closed once. | | |
| N-06 | Force-quit during monitoring, relaunch. | Last session is closed with a sensible `endedAt` (or recovered); no duplicate session; data intact. | | |
| N-07 | Focus / Do Not Disturb on, trigger reminder in background. | *Observe*: notification silenced per Focus; app does not misuse time-sensitive interruption level unless decided. | | |

What we can and cannot claim: per D-010 the MVP monitors only while the app is open, and the UI
and App Store text must say so. Background monitoring would need a new decision, a background
mode Apple accepts for this use, and N-03/N-04 passing on hardware.

### 2.7 Battery (60-minute session)

Goal: measure the cost of one hour of monitoring on the iPhone and the AirPods.

| ID | Steps | Expected | Result | Notes |
|---|---|---|---|---|
| B-01 | **Control run.** Charge iPhone and AirPods to 100%, unplug. AirPods in ears playing nothing, Align closed, screen on with auto-lock off and brightness fixed (~50%), same Wi-Fi, Low Power Mode off. After 60 min record iPhone % and AirPods % (Settings → Battery / Batteries widget). | Baseline numbers recorded. | | |
| B-02 | **Monitoring run.** Same conditions as B-01 (same day, same room temperature), Align monitoring in foreground for 60 min. Record iPhone %, AirPods %, Settings → Battery → last 24 h → Align's share and "Screen On / Background" minutes. | Extra drain vs B-01 recorded. Target (proposal): ≤ 5 percentage points per hour on the iPhone attributable to Align; no noticeable thermal warmth. | | |
| B-03 | **Background check**: start monitoring, then background the app and lock the phone for 60 min (D-010: monitoring should be paused). | Align's background minutes in Settings → Battery ≈ 0 and drain ≈ B-01 control. Anything else means the app keeps working in the background contrary to D-010. | | |
| B-04 | **Xcode Energy gauge.** Run from Xcode (Debug navigator → Energy Impact) for 10 min of monitoring; prefer a wireless debugging connection, because a cable charges the phone. | Record the typical level (Low / High / Very High) and the CPU % during steady monitoring. Expected: Low; CPU well under 10%. Spikes only on screen transitions. | | |
| B-05 | Diagnostics during B-02: sample rate and largest gap at minutes 1, 30, 60. | Rate stable; no growing gaps (no throttling, no leak). Note memory in Xcode if attached. | | |

Notes: the battery percentage has 1% resolution, so single runs are noisy; repeat B-01/B-02 at
least twice before drawing conclusions. Settings → Battery attributes usage per app per hour
only after the fact (it can lag up to an hour).

### 2.8 Offline operation

| ID | Steps | Expected | Result | Notes |
|---|---|---|---|---|
| O-01 | Airplane mode on, then Bluetooth back on (Wi-Fi off). Reconnect AirPods; run C-01, T-04, T-06; open History. | Everything works; no error or spinner about connectivity; data saved. | | |
| O-02 | After a normal day of use, open Settings → Privacy & Security → App Privacy Report → Align. | **No** network domains contacted (Phase 1 has no network code). Any domain listed is a privacy defect. | | |

### 2.9 Data and privacy checks on device

| ID | Steps | Expected | Result | Notes |
|---|---|---|---|---|
| P-01 | Privacy & Data → delete all data. Relaunch. | History empty; baseline gone (needs calibration); settings either reset or kept as the screen states. | | |
| P-02 | Delete the app, reinstall. | No data survives (no iCloud/Keychain persistence in Phase 1). | | |
| P-03 | Check the motion and notification prompts' text. | Matches the purpose strings in `docs/research/privacy-review.md`. | | |

## 3. Defect reporting

Record defects in the Notes column and as a short entry in `docs/agents/blockers.md` (if it
blocks a task) with: case ID, build SHA, device/iOS, AirPods firmware, steps, expected, actual,
and a Diagnostics screenshot or screen recording where possible.

## 4. Exit criteria for Phase 1

- CI green on `main` for `hygiene`, `python`, `swift-package`, `ios-app` (Linux job may still be
  non-blocking).
- Fixture replay parity passing (A-03).
- Device cases D-01…D-04, D-06, C-01…C-04, T-01…T-08, R-02…R-06, R-08, N-02, O-01, O-02, P-01
  passed on at least one iPhone + AirPods Pro combination; N-03/N-04 and B-01…B-04 recorded
  (they are observations, but the app's claims must match them).
- T-01 confirms or corrects `HeadAxisConvention.airPodsDefault` (S-05).
