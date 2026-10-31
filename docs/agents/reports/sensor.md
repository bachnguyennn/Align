# Sensor agent report (S-01 – S-04)

Date: 2026-10-31. Agent: Sensor (Agent 3).

## Status in one line

Code, tests and research are written and committed. **None of the Swift has been compiled or
run.** This machine has no Swift toolchain (X-01), so all of it waits on CI. Hardware behaviour
is unverified (S-05 / X-02). Suggested task-board status: S-01 `in review`, S-02/S-03/S-04
`in review` (pending CI), S-05 `blocked`.

## Deliverables

| Task | Files |
|---|---|
| S-01 | `docs/research/airpods-motion-feasibility.md` |
| S-02 | `ios/AlignKit/Sources/Sensors/RealAirPodsSensorProvider.swift` (`#if os(iOS)`) |
| S-03 | `ios/AlignKit/Sources/Sensors/MockScenario.swift`, `MockMotionGenerator.swift` (pure, internal), `MockSensorProvider.swift` |
| S-04 | `ios/AlignKit/Sources/Sensors/SampleRateMeter.swift` |
| Tests | `ios/AlignKit/Tests/SensorsTests/MockMotionGeneratorTests.swift`, `MockSensorProviderTests.swift`, `SampleRateMeterTests.swift`, `TiltTestHelpers.swift` |

Removed placeholders: `Sources/Sensors/Sensors.swift` and `Tests/SensorsTests/SensorsPlaceholderTests.swift`.

### Public API

The API matches `sensor-contracts.md` §1, with a few additive extras:

- `MockSensorProvider`: also `public let sampleRateHz`, `public let timeScale`.
- `SampleRateMeter`: also `public let window`, `public mutating func reset()`,
  `public var sampleCount: Int`.
- `MockMotionGenerator` and `MockHeadPose` are `internal` (tests use `@testable import`).

### Behaviour notes

- **Real provider**
  - The first event after `start()` is one of `.unavailable(.motionNotSupported)`
    (`!isDeviceMotionAvailable`), `.unavailable(.notAuthorized)` (denied or restricted), or
    `.waitingForHeadphones`.
  - It moves to `.connected` on `didConnect` **or** on the first sample, because there is no
    "is connected" API. `didDisconnect` moves it back to `.waitingForHeadphones`.
  - A handler error stops updates. It maps to `.unavailable(.notAuthorized)` if authorization is
    now denied or restricted, and to `.failed(message:)` otherwise.
  - Updates come on `OperationQueue.main`. Delegate callbacks go through an `NSObject` proxy that
    hops to the main queue.
  - Core Motion is stopped on `stop()`, on a new `start()`, and when the consumer stops
    iterating (`onTermination`). Nothing runs while idle.
  - The buffer is `.bufferingNewest(500)`, about 20 s at 25 Hz.
- **Mock**
  - Deterministic noise is a seeded SplitMix64 hash of (seed, time in ms, channel), plus seeded
    slow sinusoidal sway. There is no mutable RNG state, so any instant can be queried in tests.
  - Timestamps start at `systemUptime` and advance by `1/sampleRateHz` of *simulated* time. The
    timer sleeps `1/(sampleRateHz × timeScale)`.
  - Changing `scenario` while streaming restarts the timeline on the same stream. Timestamps stay
    monotonic.
  - `.unavailable` and `.permissionDenied` start no timer.
- **Mock geometry**
  - The world frame is Z-up and the neutral head frame equals the world frame.
  - Attitude maps head to world. The pose is a rotation vector
    `forwardAxis·f + lateralAxis·l`, then a heading turn about world Z.
  - Gravity is `q.conjugate.rotate((0, 0, −1))`.
  - A mock +20° forward tilt reads +20° under the convention it was generated with. This is
    tested against an independent gravity-based reference.

## Verified vs. not verified

| Item | Status |
|---|---|
| Swift compiles (Xcode 15/16, iOS and macOS) | **Not verified.** No compiler here. CI must run `swift build`/`swift test` (macOS) and an iOS build that includes `RealAirPodsSensorProvider` |
| SensorsTests pass | **Not run.** No results to report |
| Mock geometry maths | Checked numerically with a Python port in my scratchpad (not committed). A +20° forward pose gives gravity (0, −0.3420, −0.9397), and the gravity-derived tilt is 20.000°. Lateral and combined poses and heading invariance check out. Over a 120 s noisy slouch cycle the noise moves tilt off the script by at most 0.74° (tests allow 1.5°) |
| Handedness argument in §5.3 | Checked numerically (Python): chin-down axis × right-ear-down axis = down |
| Apple API names and signatures | Read from Apple's documentation JSON: `authorizationStatus()` (class func), `isDeviceMotionAvailable` (instance), `startDeviceMotionUpdates(to:withHandler:)`, delegate methods, `CMDeviceMotion.SensorLocation` cases `.default/.headphoneLeft/.headphoneRight` (iOS 14+), `CMLogItem.timestamp` (since boot) |
| Axis signs, sample rate, disconnect, lock and background behaviour | **Unverified.** Needs hardware. Protocol in the feasibility doc §8 |

### Compile risks the Lead and QA should watch in CI

1. `MainActor.assumeIsolated` (Swift 5.9 stdlib, fine for iOS 17) is used inside the Core Motion
   handler and the delegate proxy. If the iOS build complains, the fallback is
   `Task { @MainActor in ... }`, which loses strict FIFO order.
2. `{ () -> Void in self?.handleUpdate(...) }`: a single-expression closure whose
   `Optional<Void>` result is discarded. This should be fine.
3. `SensorsTests` imports `AlignCore` while the test target depends only on `Sensors`. This
   relies on transitive module visibility, as the original placeholder did. If it fails, add
   `"AlignCore"` to the `SensorsTests` dependencies in `Package.swift`. That file is not mine.
4. The async tests (`MockSensorProviderTests`) take real time: under 1 s total at
   `timeScale: 10`. Each has a 5 s watchdog that calls `stop()` so it cannot hang.

## Known limitations

- **Background or lock screen:** not supported or claimed. The provider simply stops receiving
  if iOS suspends the app. The app should `stop()` on `.background` (see the feasibility doc §7).
- **Connected state:** inferred (first sample or `didConnect`). A late in-flight sample after
  `didDisconnect` could briefly flip the state back to `.connected`.
- **Stall watchdog:** there is none. If AirPods stop sending without `didDisconnect`, the state
  stays `.connected`. The pipeline's `maxSampleGap` covers detection. A watchdog can be added
  once S-05 shows whether it is needed.
- **Connection status updates:** `startConnectionStatusUpdates()` is not used, so connection
  state is only known while streaming.
- **Bud hand-off:** WWDC23 says one bud streams at a time. Whether the frame changes on hand-off
  is unknown.

## Proposed AlignCore contract changes (Lead decides)

1. **`HeadAxisConvention.airPodsDefault` is physically inconsistent (high priority).**
   - Apple's illustration shows a right-handed frame with +Z up when worn, so `+X × +Y = +Z`.
   - But (chin-down axis) × (right-ear-down axis) must equal *down*, i.e. (0, 0, −1).
   - So `forwardAxis = +X` and `lateralAxis = +Y` cannot both be right; exactly one sign is
     wrong.
   - Proposal: change the default to **H1, `forwardAxis = (−1, 0, 0)`, `lateralAxis = (0, 1, 0)`**
     (+X = right ear, +Y = nose). It matches two community reports that pitch is negative when
     looking down.
   - Keep the "UNVERIFIED (S-05)" note.
   - Add an AlignCore test asserting `forwardAxis.cross(lateralAxis) ≈ (0, 0, −1)` for whichever
     default is chosen.
   - Alternative H2 is `(+1, 0, 0)` / `(0, −1, 0)`.
   - The mock follows `airPodsDefault` automatically, and no Sensors code or test depends on
     which hypothesis is chosen.
2. Optional: a doc comment on `MotionSample.attitude` saying the direction (head→world vs.
   world→head) of `CMAttitude.quaternion` is unverified. Nothing in the pipeline should depend
   on it (D-005).

## Messages to other agents

- **Algorithm:**
  - Axis convention: the signs are **unconfirmed**, and the current default is
    internally inconsistent (see above).
  - Make the pipeline take `configuration.axes` everywhere, and don't hard-code ±X/±Y.
  - Expect a reported **~25 Hz** with jitter, unconfirmed. Use timestamps, not sample counts.
  - Consider treating a change in `sample.sensorLocation` like a short interrupt (reset the
    filter) until S-05 shows hand-off does not shift gravity.
  - Mock noise for fixtures and comparisons: sway ≤ 0.6° forward and ≤ 0.4° lateral (0.07 and
    0.19 Hz), jitter ±0.15° uniform, gyro noise ±0.01 rad/s, user acceleration ±0.005 g.
  - Scenario timelines are in `MockScenario.swift`.
- **Frontend:**
  - Info.plist must have `NSMotionUsageDescription`. Suggested text is in the feasibility doc
    §10.
  - **No `UIBackgroundModes`.** Monitoring is foreground-only. Stop the provider on
    `.background` and restart on `.active`.
  - Call `PostureMonitor.interrupt(at:)` on `.waitingForHeadphones`, `.failed` and stop.
  - Use `MockSensorProvider` in the simulator and previews. `timeScale: 10` makes demos fast.
  - For S-05, please give the Diagnostics screen (F-02) a "capture mean gravity (1 s)" button
    and show `forwardAxis = normalize(g_chinDown × g_neutral)` /
    `lateralAxis = normalize(g_rightEarDown × g_neutral)` (feasibility doc §5.4 and §8 step 3).
  - The Diagnostics screen should also show `SampleRateMeter.samplesPerSecond`, `largestGap` and
    `sensorLocation`.
- **QA:**
  - CI must build the Sensors target for iOS too (the macOS `swift build` skips
    `RealAirPodsSensorProvider` because of `#if os(iOS)`).
  - The device protocol in the feasibility doc §8 can feed `test-plan.md`.
- **User (S-05):** please run the feasibility doc §8 on your iPhone and AirPods Pro, especially
  step 3 (axes). Results go in §9.

## Commits (branch `worktree-agent-a05d8e9affcab3718`)

- `38ec34f` Add sensor providers, mock scenarios and sample rate meter
- `deea0c1` Add Sensors unit tests
- `36d167c` Add AirPods motion feasibility research and axis-convention notes
- (this report) Add Sensor agent report
