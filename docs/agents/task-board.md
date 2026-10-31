# Task board

Status: `todo` · `in progress` · `in review` · `done` (verified) · `blocked`.
"Verified" means the verification method actually ran; "written" work that has not been
compiled or run is at most `in review`.

| ID | Task | Agent | Depends on | Status | Deliverables | Verification |
|---|---|---|---|---|---|---|
| L-01 | Architecture, contracts, package skeleton | Lead | — | done | `docs/agents/*`, `ios/AlignKit` skeleton, AlignCore types | Review; CI compile (L-03) |
| L-02 | Merge agent branches, resolve conflicts | Lead | S-*, A-*, F-*, Q-* | done | `main` | CI green |
| L-03 | Integration check: package tests + app build in CI | Lead | Q-01 | done (run 41197474300) | `integration-log.md` | GitHub Actions run |
| S-01 | AirPods motion API feasibility research | Sensor | — | in review | `docs/research/airpods-motion-feasibility.md` | Cited Apple docs; hardware items marked unverified |
| S-02 | `RealAirPodsSensorProvider` | Sensor | L-01 | compiles (iOS Sim, CI run 41179990821); device untested | `Sources/Sensors` | CI compile (iOS); device test S-05 |
| S-03 | `MockSensorProvider` + scenarios | Sensor | L-01 | done (CI tests pass) | `Sources/Sensors` | `SensorsTests` |
| S-04 | `SampleRateMeter` | Sensor | L-01 | done (CI tests pass) | `Sources/Sensors` | `SensorsTests` |
| S-05 | Hardware check: axes, sample rate, lock/background behavior | Sensor + user | F-02, physical iPhone + AirPods Pro | blocked (needs device) | Feasibility doc results | Manual device protocol |
| A-01 | Python reference pipeline + synthetic fixture generator | Algorithm | L-01 | done (104 pytest pass); superseded by A-05 | `analytics/experiments` (removed), `shared/fixtures/motion` | pytest (local) |
| A-02 | Swift `PostureMonitor` + components | Algorithm | L-01 | done (CI tests pass) | `Sources/PostureDetection` | `PostureDetectionTests` in CI |
| A-03 | Cross-language fixture replay parity | Algorithm | A-01, A-02 | done (8 fixtures, Swift = reference) | Swift tests replaying fixtures | CI |
| A-04 | Evaluation report; head tilt vs. translation note | Algorithm | A-01 | done (synthetic data only) | `docs/research/algorithm-evaluation.md` | Reproducible script output |
| A-05 | Port reference tools to Java; remove Python (D-015) | Algorithm | A-01 | done (177 JUnit pass, all 8 reference blocks reproduced exactly) | `analytics/align-tools` | CI `java` |
| F-01 | XcodeGen project + app shell + navigation | Frontend | L-01 | done (CI build) | `ios/project.yml`, `ios/AlignApp` | CI build |
| F-02 | Diagnostics screen (Phase 0 prototype: live raw values + rate) | Frontend | S-02, S-04 | builds + unit tests pass; not run on device | `Features/Diagnostics` | CI build; device S-05 |
| F-03 | Onboarding, permissions, compatibility | Frontend | F-01 | builds + unit tests pass; not run on device | `Features/Onboarding` | CI build; simulator |
| F-04 | Calibration screen | Frontend | A-02 | builds + unit tests pass; not run on device | `Features/Calibration` | CI build; mock run |
| F-05 | Dashboard + live monitoring + orientation indicator | Frontend | A-02, S-03 | builds + unit tests pass; not run on device | `Features/Dashboard`, `Features/Monitoring` | CI build; mock run |
| F-06 | MonitoringController, session lifecycle, SwiftData | Frontend | A-02 | builds + unit tests pass; not run on device | `App/`, `Persistence/` | `AlignAppTests` |
| F-07 | Reminder notifications + haptics | Frontend | F-06 | builds + unit tests pass; not run on device | `Notifications/` | `AlignAppTests`; device |
| F-08 | History & analytics (Swift Charts) | Frontend | F-06 | builds + unit tests pass; not run on device | `Features/History` | CI build |
| F-09 | Settings, Privacy & Data | Frontend | F-06 | builds + unit tests pass; not run on device | `Features/Settings`, `Features/Privacy` | CI build |
| Q-01 | CI: reference tool tests (Java, was Python), Swift package tests, app build + unit tests | QA | L-01 | done (CI green) | `.github/workflows` | Green run on GitHub |
| Q-02 | AlignCore unit tests (geometry) | QA | L-01 | done (CI tests pass) | `Tests/AlignCoreTests` | CI |
| Q-03 | Test plan incl. device protocol (disconnects, permissions, cooldown, battery) | QA | — | in review | `docs/agents/test-plan.md` | Review |
| Q-04 | Privacy review | QA | F-06 | in review (initial) | `docs/research/privacy-review.md` | Review |
| B-*, D-* | Backend sync + analytics pipeline | Backend, Data | Phase 1 | deferred (D-008) | — | — |
