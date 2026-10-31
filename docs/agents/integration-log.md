# Integration log

Entries are added by the Lead Architect after each merge, recording what was merged, what was
verified (with CI run links), and what failed.

| Date | Merge | Verification | Result |
|---|---|---|---|
| 2026-10-31 | Sensor agent branch (S-01…S-04) → main | Reviewed diff; fixed one test that hardcoded the old axis sign (D-011). No compiler available locally; CI not yet merged. | Merged, unverified until CI (Q-01) |
| 2026-10-31 | QA agent branch (Q-01…Q-04) → main | Workflow YAML parsed, shell checked with shellcheck by QA locally; first GitHub run triggered by this push. | Merged; see next entry for CI result |
| 2026-10-31 | CI run #1 (b4c5abc) | macOS package build + 0 failures; iOS Simulator package build OK; Linux failed: sync `@MainActor` XCTest method not callable from Linux test discovery. | Fixed in 9057039 |
| 2026-10-31 | CI run #2 (9057039) — https://github.com/bachnguyennn/FixMySpine/actions/runs/41179990821 | All 5 jobs green; XCTest: 76 tests, 0 failures (AlignCore + Sensors). App and Python jobs skipped (not merged yet). | Green |
| 2026-10-31 | Algorithm (A-01…A-04) + Frontend (F-01…F-09) → `integration` | CI run 41180412382: all jobs green, first full app build; package 126 tests, 0 failures. | Green |
| 2026-10-31 | D-016 deferred reminder, Strict 12°, app test summary → `integration` | CI run 41197474300: all green; package 127 tests, app 32 tests, 0 failures; pytest 104 pass locally. | Green → fast-forwarded to `main` |
| 2026-10-31 | Java reference tools (D-015) → `integration` | CI run 41224929995: all 6 jobs green; JUnit 177, package 127, app 32, pytest 104; 0 failures. | Green → fast-forwarded to `main` |
| 2026-10-31 | Python tools and `python` CI job removed; edge test uses 32.05 − 2.05 | CI run 41225574214: all 5 jobs green; JUnit 177, package 127, app 32; 0 failures. CoreData "Failed to stat default.store" annotations come from the app host's first SwiftData launch on a fresh simulator (harmless). | Green → `main` |
| 2026-10-31 | Phase 2 sync server (B-01) → `integration` | CI run 41246932183: all 6 jobs green; server 154 tests on PostgreSQL 16.15, JUnit 177, package 130, app 32. | Green → `main` |
| 2026-10-31 | D-017 nod axis calibration + quantile (A-06) → `integration` | CI run 41247526330: all 6 jobs green; Swift compiled first time; package 158 (macOS and Linux), app 32, JUnit 284, server 154. | Green → `main` |
