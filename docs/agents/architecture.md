# Align — Architecture

Owner: Lead Architect. Status: v1 (Phase 0/1).

Align is an iOS 17+ wellness app that reads head motion from AirPods Pro via
`CMHeadphoneMotionManager`, compares head tilt to a calibrated neutral position, and gently
reminds the user when a forward or sideways tilt is sustained. It is not a medical device.

## Principles

1. **On-device first.** Sensing, calibration, detection, reminders and storage run on the
   phone. No network is needed for the MVP. Raw motion never leaves the device.
2. **Pure core.** The posture pipeline is platform-independent Swift with no Core Motion or
   UIKit imports, so it is unit-tested on macOS/Linux and replayed from fixtures.
3. **Contracts before code.** Shared types live in `AlignCore`; changing them needs an entry in
   `decisions.md`.
4. **Honest status.** Nothing is "working" until verified by CI or on a physical device.

## Data flow

```
AirPods Pro IMU
  → CMHeadphoneMotionManager            (Sensors: RealAirPodsSensorProvider)
  → SensorEvent stream (MotionSample)    (AlignCore contract; MockSensorProvider in simulator)
  → PostureMonitor.process(_:)           (PostureDetection)
      MotionFilter → CalibrationService → tilt estimation → PostureDetector → ReminderDecisionEngine
  → PostureUpdate                        (AlignCore contract)
  → MonitoringController (@Observable)   (App)
      ├─ SwiftUI dashboard / live view
      ├─ ReminderNotifier (local notifications + haptics)
      └─ SwiftData store (MonitoringSession, PostureEvent)
  → History & analytics computed on device from stored sessions/events
  (Phase 2: optional FastAPI sync of aggregated sessions/events only)
```

## Modules

| Module | Location | Depends on | Owner |
|---|---|---|---|
| AlignCore | `ios/AlignKit/Sources/AlignCore` | Foundation | Lead Architect |
| PostureDetection | `ios/AlignKit/Sources/PostureDetection` | AlignCore | Algorithm |
| Sensors | `ios/AlignKit/Sources/Sensors` | AlignCore, CoreMotion (iOS only) | Sensor |
| Align app | `ios/AlignApp` (XcodeGen `ios/project.yml`) | all three, SwiftUI, SwiftData, Charts, UserNotifications | Frontend |
| Java reference + generator + evaluation | `analytics/align-tools` | Java 21, Maven, Jackson, JUnit 5 | Algorithm |
| Replay fixtures | `shared/fixtures/motion` | — | Algorithm |
| CI | `.github/workflows` | — | QA |

## Tilt estimation (D-005)

Tilt is computed from the **gravity direction in the head frame**, not by comparing attitude
quaternions. The baseline is the mean unit gravity vector during calibration. The rotation that
takes the baseline gravity to the current gravity is expressed as a rotation vector and projected
onto `HeadAxisConvention.forwardAxis` and `.lateralAxis`. Benefits: heading (turning the head)
is excluded by construction, no Euler angles (no gimbal lock or ±180° wrap), and a stored
baseline remains valid when Core Motion's arbitrary heading reference changes between sessions.
Note that the head rotates opposite to the gravity vector seen in the head frame; signs are set
by `HeadAxisConvention` and must be verified on hardware (S-05).

## Time

All pipeline timing uses `MotionSample.timestamp` (monotonic seconds since boot). The app turns
these into `Date`s for storage with `Date(timeIntervalSinceNow: timestamp - ProcessInfo.processInfo.systemUptime)`.

## Repository layout

```
ios/AlignKit/        Swift package: AlignCore, PostureDetection, Sensors (+ tests)
ios/AlignApp/        SwiftUI app sources (Features/, Persistence/, Notifications/, App/)
ios/AlignAppTests/   App-level unit tests
ios/project.yml      XcodeGen spec (the .xcodeproj is generated, not committed)
analytics/           Java reference implementation, fixture generator and evaluation (align-tools)
shared/fixtures/     Replayable motion fixtures used by the Java and Swift tests
docs/agents/         Contracts, decisions, task board, logs, agent reports
docs/research/       Feasibility, algorithm evaluation, privacy review
.github/workflows/   CI
backend/             Phase 2 (not started)
```
