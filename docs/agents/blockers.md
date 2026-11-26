# Blockers

| ID | Blocker | Impact | Owner | Status |
|---|---|---|---|---|
| X-01 | Development machine is Windows with no Swift/Xcode toolchain. | Swift code cannot be compiled locally; all Swift verification happens in GitHub Actions (macOS runners). | Lead | Mitigated (CI). The 2026-10-31 hardware run was built on a Mac with Xcode 27.1. |
| X-02 | Physical iPhone + AirPods Pro testing must be done by the user on their Mac/iPhone. | Axis convention, real sample rate and background behavior stay unverified until then (S-05). | User | Partly resolved: first run 2026-10-31 (`reports/hardware-test-2026-10-31.md`); the rest is tracked in issue #4 |
| X-03 | `gh` CLI is not authenticated, so CI logs are not readable from the dev machine (run status and annotations are public). | Slower diagnosis of CI failures. | User | Open |
