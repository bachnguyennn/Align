# Integration log

Entries are added by the Lead Architect after each merge, recording what was merged, what was
verified (with CI run links), and what failed.

| Date | Merge | Verification | Result |
|---|---|---|---|
| 2026-10-31 | Sensor agent branch (S-01…S-04) → main | Reviewed diff; fixed one test that hardcoded the old axis sign (D-011). No compiler available locally; CI not yet merged. | Merged, unverified until CI (Q-01) |
| 2026-10-31 | QA agent branch (Q-01…Q-04) → main | Workflow YAML parsed, shell checked with shellcheck by QA locally; first GitHub run triggered by this push. | Merged; see next entry for CI result |
| 2026-10-31 | CI run #1 (b4c5abc) | macOS package build + 0 failures; iOS Simulator package build OK; Linux failed: sync `@MainActor` XCTest method not callable from Linux test discovery. | Fixed in 9057039 |
| 2026-10-31 | CI run #2 (9057039) — https://github.com/bachnguyennn/FixMySpine/actions/runs/41179990821 | All 5 jobs green; XCTest: 76 tests, 0 failures (AlignCore + Sensors). App and Python jobs skipped (not merged yet). | Green |
