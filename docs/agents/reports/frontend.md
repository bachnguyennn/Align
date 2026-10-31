# Frontend agent report (F-01 … F-09)

Branch: `worktree-agent-a9cc260db29748aef`. Status of every item: **written, not compiled**.

## Verification — read this first

- This was written on Windows with **no Swift compiler or Xcode**. Nothing here has been
  compiled, run, previewed or tested. No test results exist yet.
- The Sensors API was checked against the code merged on `main` (`MockSensorProvider`,
  `MockScenario`, `SampleRateMeter`, `RealAirPodsSensorProvider`): the signatures I use match.
- `PostureMonitor` was **not** on `main` while I worked. I coded against
  `sensor-contracts.md` §2 exactly. The app will only build once the Algorithm branch is merged.
- The first real check will be the CI `ios-app` job (`xcodegen generate`, `xcodebuild build`,
  `xcodebuild test`). Expect a few rounds of fixes. I avoided iOS 18-only APIs and checked each
  API against what I know of the iOS 17 SDK, but that is not the same as compiling.

## Deliverables

| Task | Files | Notes |
|---|---|---|
| F-01 | `ios/project.yml` | Project `Align`, app target `Align` (iOS 17, iPhone only, `com.bachnguyennn.align`), generated `AlignApp/Info.plist` with `NSMotionUsageDescription` and `UILaunchScreen`, local package `AlignKit` (AlignCore, PostureDetection, Sensors), `AlignAppTests` (hosted unit tests), shared scheme `Align` whose test action runs `AlignAppTests`. No background mode (commented note; D-010). `PrivacyInfo.xcprivacy` copied as a resource. |
| F-02 | `Features/Diagnostics/` | Source, motion availability, authorization, connection, streaming earbud (`sensorLocation`), sample rate and largest gap (`SampleRateMeter`), timestamp, attitude, gravity, rotation rate, user acceleration, monitor tilt. **Axis check**: "Capture neutral gravity", then nod down / look up / tilt right / turn, with live forward/lateral signs from a calibration-free estimate (`AxisCheck`, D-005 method) next to the `PostureMonitor` values. Demo controls when the mock is active. |
| F-03 | `Features/Onboarding/` | Welcome → privacy + not-medical note → AirPods & permissions. Gate via `@AppStorage("align.hasCompletedOnboarding")`. Permissions screen: motion availability and access (starts the sensor to trigger the prompt), connection, notification permission, Open Settings, headphone examples from the feasibility research, troubleshooting tips. |
| F-04 | `Features/Calibration/` | Instructions, progress ring bound to `.calibrating(progress)`, success view, failure message per `CalibrationFailure` with retry, VoiceOver announcements. |
| F-05 | `Features/Dashboard/`, `Features/Monitoring/` | Dashboard: sensor status, current tilt, posture state, session controls (start/pause/resume/stop), monitored time, % in range, reminders, last reminder, "Paused — Align monitors while the app is open". Live view: 2D head indicator (down = forward, sideways = lateral), dashed threshold outline (forward/backward/lateral thresholds), numeric degrees, marker changes shape when outside range, Reduce Motion respected, VoiceOver value such as "Head tilted 18 degrees forward. Outside your range." |
| F-06 | `App/MonitoringController.swift`, `App/AppEnvironment.swift`, `Persistence/` | See "MonitoringController" below. SwiftData `MonitoringSession` + `PostureEvent` per data-contracts.md; settings, `PostureConfiguration` and `NeutralBaseline` as JSON in UserDefaults. |
| F-07 | `Notifications/ReminderNotifier.swift` | Authorization request, immediate local notification (nil trigger, fixed identifier so reminders replace each other), light haptic when active, foreground banner via `willPresent` (`.banner, .list`, plus `.sound` if enabled). Copy: "Time for a posture reset — lift your head and relax your shoulders." |
| F-08 | `Features/History/` | Swift Charts: monitored vs. sustained-tilt minutes per day (grouped bars) and reminders per day for the last 7 days, text summary, session list and session detail with tilt episodes. |
| F-09 | `Features/Settings/`, `Features/Privacy/` | Presets Gentle/Balanced/Strict (20/15/10°, 60/30/20 s), fine-tune steppers, cooldown 2–30 min, sound/haptics. Privacy & data: what is stored, delete all history, reset calibration, reset settings (separate, D-012), demo mode. Diagnostics reachable from Settings. |
| Tests | `ios/AlignAppTests/` | `SessionAccumulator` (state attribution, gap cap, continuity breaks, out-of-order, 25 Hz stream), `MonotonicClock` (incl. architecture.md formula), `DailySummaryBuilder`, preset mapping and matching, `AppSettings` decoding, `SettingsStore` persistence / reset / axes override, `Format`, `AxisCheck` signs. |
| Privacy | `ios/AlignApp/PrivacyInfo.xcprivacy` | No tracking, no collected data, UserDefaults CA92.1, SystemBootTime 35F9.1. |

## MonitoringController behaviour

- **Provider**: `MockSensorProvider(scenario: .manual)` in the simulator or in demo mode,
  `RealAirPodsSensorProvider()` otherwise. Switching demo mode stops any session first, so real
  and simulated data are never mixed.
- **Streaming on demand**: screens acquire and release the sensor (`dashboard`, `liveView`,
  `calibration`, `diagnostics`, `permissions`, `session`). Streaming stops when none hold it.
  The stream is read in a main-actor `Task`; a generation counter drops events from an old stream.
- **Accounting** (`SessionAccumulator`): each interval between sample updates goes to the state
  at the *start* of the interval. Steps are capped at `configuration.maxSampleGap`. `.neutral` and
  `.deviating` count as within threshold, `.sustainedTilt` as sustained, and both as monitored.
  Interrupts, pauses and disconnects break continuity.
- **Interrupts**: `monitor.interrupt(at:)` on pause, stop, stream stop, and any connection change
  away from `.connected` (`.waitingForHeadphones`, `.failed`, `.idle`, `.unavailable`).
- **Foreground-only (D-010)**: leaving `.active` pauses a running session (reason `appInactive`)
  and saves. `.background` also stops the provider. `.inactive` alone does not stop it, because
  system alerts (including the Motion & Fitness prompt) make the app briefly inactive and
  stopping there could break the permission flow. Returning to `.active` restarts streaming and
  **resumes the session automatically** if it was paused only by leaving the app.
- **Outside a session** the monitor still runs so the dashboard and live view can show tilt.
  Reminders and episodes are ignored then. If the monitor issued a reminder while paused, its
  cooldown is reset on resume so the user isn't silently locked out.
- **Persistence**: session row created on start, totals saved every 15 s of sample time, on
  reminders, pause, stop and when the app leaves the foreground. Episodes become `PostureEvent`s
  with dates from `MonotonicClock` (same as architecture.md's formula). `reminderTriggered` is
  false if reminders were turned off. Sessions left open by a crash are closed on launch with
  `endedAt = startedAt + monitored`.
- **Calibration**: starting calibration pauses a running session. Success stores the baseline in
  UserDefaults and updates the active session's `calibrationVersion`. Resetting calibration
  creates a new `PostureMonitor` with no baseline.
- **Axes (D-011)**: never hard-coded. On load, `configuration.axes` is always replaced by
  `HeadAxisConvention.airPodsDefault`, so a stored configuration cannot freeze an old convention.

## Assumptions about other modules

- `PostureMonitor` exactly as in sensor-contracts.md §2: `init(configuration:baseline:)`,
  settable `configuration`, `baseline`, `state`, `beginCalibration()`, `cancelCalibration()`,
  `process(_:) -> PostureUpdate`, `interrupt(at:) -> PostureUpdate`, `resetCooldown()`. It is a
  non-Sendable class used only from the main actor.
- After `cancelCalibration()`, `state` reflects the existing baseline (or `.needsCalibration`).
- `interrupt(at:)` is safe to call at any time, including with no data or no baseline.
- `MockSensorProvider.isMotionAvailable` is true for `.manual` (it is on `main`).

## Proposed contract / repo changes (for the Lead)

1. **`.gitignore`**: add `ios/AlignApp/Info.plist`. XcodeGen writes it during `generate`, and it
   shouldn't be committed (I can't edit `.gitignore`).
2. **`PostureMonitor.resetBaseline()`** (optional): the app has to recreate the monitor to clear a
   baseline, which also resets the version count, so the next calibration is version 1 again.
   Either accept that or add a reset that keeps the version counter.
3. **`SWIFT_VERSION`**: the brief said 5.9, but Xcode only accepts language modes 4, 4.2, 5 or 6.
   I set `"5.0"` (Swift 5 mode, compiled by the Swift 5.9/5.10/6 compilers) plus
   `SWIFT_STRICT_CONCURRENCY: minimal`. Please confirm.
4. **Data contract**: the sensitivity preset is *derived* from the stored configuration (it matches
   when forward, lateral and hold time equal a preset) instead of being stored separately. That
   prevents the two from disagreeing. data-contracts.md lists "sensitivity preset" as stored;
   update the wording or tell me to store it.
5. **Backward threshold**: presets set backward (looking up) to threshold + 5° (Balanced = 20°,
   the package default). Fine-tune doesn't expose it.

## Decisions needed

- Auto-resume after returning to the app (current) vs. leaving the session paused until the user
  taps Resume.
- `.inactive` keeps the provider running (only `.background` stops it), as explained above. The
  Lead's note said to stop it on leaving `.active`; I deviated on purpose for the permission
  prompt. Easy to change in `AlignApp.swift`.

## Build on a Mac

```sh
brew install xcodegen
cd ios
xcodegen generate
open Align.xcodeproj
```

Choose your Team under Signing & Capabilities for the `Align` target (or pass
`DEVELOPMENT_TEAM=XXXXXXXXXX`). Simulator without signing, as CI does:

```sh
xcodebuild test -project Align.xcodeproj -scheme Align \
  -destination 'platform=iOS Simulator,name=iPhone 15' CODE_SIGNING_ALLOWED=NO
```

In the simulator the app always uses the mock sensor. Use Home → Live view or Settings →
Diagnostics to move the simulated head with sliders or play scenarios.

## Known limitations and risks

- **Not compiled.** The likeliest trouble spots: SwiftData macros (`@Relationship` inverse,
  `@Attribute(.unique) var id`), `@Observable` + `@MainActor` with `@Bindable` key paths, the
  `UNUserNotificationCenterDelegate` completion-handler signature in the Xcode 16 SDK, and the
  XcodeGen `link: false` package dependency on the test target (added so tests can
  `import AlignCore` without linking a second copy).
- No app icon or asset catalog yet (colors are defined in code). App Store upload needs an icon.
- The 10 s on the welcome screen is fixed text; the calibration screen uses the configured value.
- Reminders are delivered only while the app is in the foreground (D-010). They appear as banners
  through `willPresent`.
- The axis check is a quick estimate for S-05. The `PostureMonitor` value is authoritative; report
  any disagreement.
- History charts recompute from all sessions on each render. That is fine for months of data, but
  might need a date-filtered `@Query` later.
- Not done: no UI tests, no snapshot tests, no localization, no developer motion recording
  (added in F-11 below).

# F-11: guided nod, sample watchdog, motion recording (D-017 (a) app side, (c), (d); D-020 UI)

Branch: `worktree-agent-aee764ee32de27b27`. Status: **written, not compiled** (Windows, no Swift
toolchain). `ios/AlignKit` is untouched; the app uses `beginAxisCalibration()`,
`cancelAxisCalibration()`, `clearLearnedAxes()`, `PostureUpdate.axisCalibrationOutcome`,
`NeutralBaseline.learnedAxes` and `AxisCalibrationService.signedYawDegrees` as they are on `main`.
No `project.yml` change: new files sit in the existing `AlignApp` / `AlignAppTests` folders, and
the tests need only `AlignCore` (the mock provider comes from `AppEnvironment.makeProvider`).

## What changed

| Area | Files | Notes |
|---|---|---|
| Nod step | `Features/Calibration/CalibrationView.swift` | After "Neutral position saved": step 2 of 2 card, `NodIllustration` (head in profile, `PhaseAnimator` nod; with Reduce Motion a static upright head plus a faint nodded copy), Start the nod, linear progress while watching, Skip. Results: All set / per-failure title and message, Try the nod again (or Calibrate neutral position for `.needsBaseline`) and Skip. VoiceOver announcements for each phase; the illustration is one labelled image element. The instructions screen (Settings → Neutral position) has a **Tilt axes** card: "Learned from your nod" / "Default", Redo nod (Do the nod when default) and Use default axes. |
| Controller | `App/MonitoringController.swift` | `AxisCalibrationPhase` (idle, waitingForSensor, inProgress, succeeded, failed, skipped); `startAxisCalibration`, `cancelAxisCalibration`, `skipAxisCalibration`, `useDefaultAxes`; `isCalibrating` = neutral or nod (blocks sessions as before). Every change of the monitor's baseline is written to `SettingsStore.baseline` at once: neutral success stores the new baseline (which has no learned axes); nod success stores `monitor.baseline` with `learnedAxes` (version + 1); Use default axes stores it after `clearLearnedAxes()`; skip changes nothing. `effectiveAxes`, `hasLearnedAxes`, `learnedAxisYawDegrees`. `handle(_:)` is now internal so tests feed events directly. |
| Watchdog | `App/SampleWatchdog.swift` | Armed by the first sample while streaming and `.connected`; ticks every 0.25 s through an injected `WatchdogTimer` (the real one is a main-actor `Task` that exists only while armed); fires once when no sample arrived for `maxSampleGap` + 0.5 s by an injected clock (arrival time, not sample timestamps), then disarms until the next sample. The controller then runs the existing interrupt path (`interruptMonitor()`: open episode closed and persisted, calibration or nod fails with `.sensorInterrupted`), clears the tilt and sample, sets `isSampleStalled` and counts `sampleStallCount`. Disarmed on any connection change away from `.connected` and on stream stop. |
| Recording | `Features/Diagnostics/MotionRecording.swift`, `DiagnosticsView.swift` | See below. |
| Diagnostics | `Features/Diagnostics/DiagnosticsView.swift` | New "Tilt axes in use" section (source, effective forward/lateral axes, learned yaw vs default via `signedYawDegrees`), watchdog status and stall count under Sensor, Axis check kept (footer now says it always uses the default axes), Record motion section. |
| Other | `SettingsView.swift`, `PrivacyDataView.swift`, `Formatting.swift`, `AppInfo.swift`, `AppEnvironment.swift` | Settings shows a "Tilt axes" row under Neutral position; Privacy & data mentions recordings; failure copy; version and model helpers; leftover recordings deleted at launch. |
| Docs | `TESTING.md`, `.github/ISSUE_TEMPLATE/hardware-test.md`, `README.md`, `docs/research/privacy-review.md` §2, §5, §10 | Nod step, "Record a session for tuning", issue template rows for nod, yaw, stalls and recordings. |

## UX copy for each nod outcome

| Outcome | Title | Message |
|---|---|---|
| prompt | Step 2 of 2: one slow nod | "Now nod slowly — chin down about 20–30°, then back up." plus why, and the 8 s window |
| `.succeeded` | All set | "Your neutral position and your nod are saved. Align now measures tilt along the axes learned from your nod." (redo: "Your nod is saved. …") |
| `.noNodDetected` | Let's try that nod again | "We didn't see a nod — try a slightly bigger, slower nod." |
| `.inconsistentMotion` | Let's try that nod again | "That looked like a sideways tilt or turn — nod straight down and up." |
| `.sensorInterrupted` | The nod didn't finish | "The AirPods connection was interrupted during the nod. Check that both AirPods are in and connected, then try again." |
| `.needsBaseline` | Neutral position needed first | "The nod is measured from your neutral position. Calibrate your neutral position first, then do the nod." (button: Calibrate neutral position) |
| skipped | Calibrated | "Your neutral position is saved (calibration N). Align is using the default axes; you can add the nod any time in Settings → Neutral position." |

## Motion recording (D-017 (d))

- Diagnostics → Record motion: explanation first (raw head motion, only for this export, stays on
  this iPhone unless shared, deleted when leaving the screen, never uploaded), length 30 s, 1 min
  or 2 min, optional note (at most 280 characters, "no names" hint), Start recording (needs a
  connected stream). While recording: progress, sample count, **Calibrate neutral now** and
  **Nod now** (so a calibration can be captured in the file; leaving Diagnostics cancels one
  started there), Stop. Then: Share recording (`ShareLink(item: URL)`), Delete recording.
- File: the documented recording format, written by hand (`MotionRecordingEncoder`) so `q` has 4
  and `g` 5 decimals (`r` 4, `t` 6) and keys keep the documented order. `config` is the full
  configuration with the documented keys only; **the D-020 drift keys are left out** because
  `PostureConfiguration.withOverrides` in align-tools rejects unknown keys (open question 1).
  `baseline` and `config` are those at the start; `actions` are stamped 1 ms after the last
  recorded sample so replay applies them at the same point. `recording`: `appVersion`
  (`CFBundleShortVersionString (CFBundleVersion)`), `device` (`uname` machine, or
  `SIMULATOR_MODEL_IDENTIFIER`), `headphones` = `"unknown"` (or `"mock sensor (demo mode)"`),
  `notes` (omitted when empty), `createdAt` (ISO 8601, UTC). File name
  `yyyy-MM-dd-recording-HHmmss.json`.
- Lifecycle: memory only while recording; then one file in `tmp/AlignMotionRecordings/` (complete
  file protection). Deleted on leaving Diagnostics, on a new recording, on Delete and at launch.
  Stops (keeping what was captured) on disconnect, stream stop or background; `.inactive` keeps
  recording. No SwiftData or UserDefaults writes (tested).

## Tests added (`ios/AlignAppTests`)

- `SampleWatchdogTests`: fires once after 1.5 s of silence (not at 1.4 s, not again), resumes on
  samples; not armed without `.connected` or without streaming; stops with the connection and
  with the stream; closes and persists the open sustained episode while the session keeps running.
- `AxisCalibrationFlowTests` (synthetic nods with an earbud yawed 20°/15°/−15°): success stores
  `learnedAxes` (reloaded from UserDefaults) and the yaw shown is 20 ± 3°; skip keeps nil; skip
  during the nod cancels it; Use default axes clears and keeps the version; neutral
  recalibration clears (version 3); still head gives `.noNodDetected`; a sideways tilt gives
  `.inconsistentMotion`; no baseline gives `.needsBaseline`; a disconnect gives
  `.sensorInterrupted`.
- `MotionRecordingEncoderTests`: decodes the JSON back: required keys, no
  `expected`/`reference`/`truth`/`generator`, config keys ⊆ documented keys, axes, null
  `maxProcessingRateHz`, baseline with learned axes, actions, sample count and rounding, note
  escaping, empty notes omitted, null baseline, empty sample list, number and string helpers.
- `MotionRecorderTests`: end to end through the controller (125 samples, a `beginAxisCalibration`
  action right after a sample, no SwiftData rows, a new recording deletes the old file, discard
  deletes the folder); stops at the chosen length, on disconnect, on background (not on
  inactive); needs a connected stream; no samples gives a failure and no file; leftover cleanup.

## Least sure it compiles (check these CI annotations first)

1. `PhaseAnimator([0.0, 25]) { angle in … } animation: { _ in Animation.easeInOut(…) }` in
   `CalibrationView.swift` (iOS 17 API, multiple trailing closures).
2. `ShareLink(item: file.url) { Label(…) }` in `DiagnosticsView.swift`.
3. `AppInfo.deviceModelIdentifier`: `withUnsafeBytes(of: info.machine)` with
   `prefix(while:)` and `String(decoding:as:)`.
4. `MotionRecorder` (`@Observable` with `nonisolated static` members and an `if let clock` init)
   and `SampleWatchdog.onStall: (@MainActor () -> Void)?`.
5. The `switch` over `Unicode.Scalar` with string-literal cases in `MotionRecordingEncoder.string`.
6. Test harness: `ControllerHarness` builds a second `MonitoringController` over an in-memory
   `AppEnvironment` (the environment's own controller is unused); tests call the now-internal
   `handle(_:)` synchronously, so the mock provider's real-time stream is never consumed.

## Open questions for the Lead

1. **D-020 keys in recordings**: align-tools' `withOverrides` throws on
   `calibrationMaxDriftDegrees` / `calibrationDriftWindow` (not in its key table on `main`), so
   recordings omit them. Once the Java side knows them, add both to
   `MotionRecordingEncoder.configKeys` and to the README key list.
2. **Release builds**: the recorder is not behind `#if DEBUG` (D-017 puts it in Diagnostics for
   testers). privacy-review R-02 said debug-only; §10 now describes the controls instead. Keep
   it, or hide it behind a developer toggle for an App Store build?
3. `data-contracts.md` still says "a developer-only motion recording for fixtures may exist behind
   an explicit toggle"; it should point to D-017 (d). I did not edit the Lead's contract.
4. On a device, check that presenting the share sheet does not fire Diagnostics' `onDisappear`
   (which deletes the file). SwiftUI does not call it for sheet presentations as far as I know,
   but that is unverified.
5. Should a watchdog stall be visible beyond "No sensor data" (for example a dashboard banner)?
   Today it shows only as the posture state and in Diagnostics.
