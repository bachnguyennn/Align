# QA / Integration / Security report

Agent 7 (QA). Tasks Q-01…Q-04. Branch `worktree-agent-a82b34e95126244a1`.

## Delivered

| Task | Files | Status |
|---|---|---|
| Q-01 CI | `.github/workflows/ci.yml`, `.gitattributes`, `scripts/ci-status.sh`, `scripts/ci/annotate-diagnostics.sh`, `scripts/ci/annotate-log-tail.sh`, `scripts/ci/pick-simulator.py` | in review (no GitHub run yet) |
| Q-02 AlignCore tests | `ios/AlignKit/Tests/AlignCoreTests/{GeometryTests,CodableTests,TestHelpers}.swift` (placeholder removed) | in review (not compiled) |
| Q-03 Test plan | `docs/agents/test-plan.md` | in review |
| Q-04 Privacy review | `docs/research/privacy-review.md` | initial, pre-implementation |

### CI design (`ci.yml`)

- Triggers: push to any branch (not tags), `pull_request`, `workflow_dispatch`. Concurrency group per
  PR/ref with `cancel-in-progress`. `permissions: contents: read`; no secrets; no `pull_request_target`.
- Actions pinned to commit SHAs: checkout v7.0.1, setup-python v7.0.0, upload-artifact v7.0.2
  (resolved through the GitHub API on 2026-10-31).
- Runners pinned: `ubuntu-24.04` (ubuntu-latest has been moving to Ubuntu 26 since 2026-10-19,
  according to a runner notice seen while testing) and `macos-15`. Xcode: `/Applications/Xcode_16.4.app`,
  the image default according to the runner-images README for macos-15 image 20261028 (I read the
  README; I did not run on the image). If the path is missing the job warns and uses the default.
- Jobs:
  - `hygiene`: fails on CRLF in the index, on a committed generated `.xcodeproj` (D-003), and on
    shellcheck warnings.
  - `python`: skips with a notice if `analytics/experiments` is missing. Installs
    `analytics/requirements.txt` if present, plus pytest and `pytest-github-actions-annotate-failures`.
    pytest exit 5 (no tests collected) becomes a warning.
  - `swift-package` (macos-15): `swift build --build-tests`, `swift test`, then an iOS Simulator
    build (`generic/platform=iOS Simulator`) of `AlignKit-Package`. It falls back to the
    `AlignCore`/`PostureDetection`/`Sensors` schemes if that scheme is missing. This compiles the
    `#if os(iOS)` Sensors code before the app exists.
  - `swift-linux`: `swift:5.10-jammy` container, `continue-on-error: true` (non-blocking for now).
  - `ios-app` (macos-15): skips with a notice if `ios/project.yml` is missing. Then
    `xcodegen generate`, a check that `ios/Align.xcodeproj` and a shared scheme `Align` exist,
    simulator selection, then separate `xcodebuild build` and `xcodebuild test` steps with
    `CODE_SIGNING_ALLOWED=NO` and an `.xcresult`.
- Simulator selection (`pick-simulator.py`): parses `xcodebuild -showdestinations` (eligible
  section only) and picks the iPhone with the newest OS, by `id`. It falls back to
  `simctl list devices available -j`, limited to runtimes no newer than the selected SDK.
- Annotations, since raw logs are not readable without auth:
  - macOS output goes through `xcbeautify --renderer github-actions` (preinstalled, v3.2.1 per
    the image README; `brew install` is the fallback).
  - Linux and shellcheck output goes through `annotate-diagnostics.sh`.
  - Every job has an `if: failure()` step. It posts one annotation with the error-like lines and
    the last 30 lines of the most recent raw log, so xcodegen, scheme, linker and pip failures
    still show up.
  - Logs and `.xcresult` are uploaded as artifacts on failure. Downloading artifacts needs a
    login, so they are for the user, not for the Lead.
- SwiftPM caching is deliberately omitted. The package has no remote dependencies, and caching
  `.build` risks stale incremental builds. Revisit when dependencies are added.

### Q-02 tests

- Vector3: operators, length, dot, normalized (including zero), right-handed cross product,
  cross-product orthogonality and the Lagrange identity.
- Quaternion:
  - identity;
  - axis-angle construction with a non-normalized axis;
  - normalized and zero cases;
  - right-hand rule (90° about z maps x→y; about x maps y→z; about y maps z→x);
  - Hamilton basis products (ij = k, ji = −k, i² = −1);
  - composition order: `(a*b).rotate(v) == a.rotate(b.rotate(v))`, with a case where the
    opposite order gives a different answer;
  - inverse of unit and non-unit quaternions, and inverse == conjugate for unit quaternions;
  - `angle` in [0, π], the shorter rotation for angles above π, normalization before `angle`,
    and q/−q equivalence;
  - two properties D-005 relies on: axis-angle from a cross product maps the source vector onto
    the target, and gravity in the head frame rotates opposite to the head.
- Codable:
  - round trips for `MotionSample` (all fields, and with optionals nil), `PostureConfiguration`
    (default and custom), `NeutralBaseline`, `HeadAxisConvention` and `TiltEstimate`;
  - decoding a hand-written fixture-style JSON;
  - rejecting an unknown `sensorLocation`;
  - pinned JSON key sets. These guard UserDefaults compatibility: the synthesized decoder
    requires every non-optional key.
- Persisted raw values are pinned (`TiltDirection`, `SensorLocation`, `CalibrationFailure`,
  sensor enums). So is default-config consistency: hysteresis < thresholds, calibration spread
  < thresholds, minimum calibration samples reachable at 25 Hz.
- D-011 (Lead request): `airPodsDefault` axes are unit and orthogonal, and
  `forwardAxis × lateralAxis ≈ (0, 0, −1)`.

## What I verified (actually ran)

- Workflow YAML parses with PyYAML. It has 5 jobs, every job has `runs-on` and `timeout-minutes`,
  and every `uses:` is pinned to a 40-character SHA.
- All 24 `run:` blocks were extracted and checked: `bash -n` passed, and shellcheck 0.11.0
  (warning level) reported nothing. Both embedded Python snippets compile.
- `scripts/*.sh` pass shellcheck at all severities (shellcheck-py, run locally).
- `annotate-diagnostics.sh` was run on sample swiftc, XCTest-on-Linux and shellcheck lines. It
  produced the expected `::error file=…,line=…,col=…::` lines with workspace-relative paths and
  `%`, `:` and `,` escaped.
- `annotate-log-tail.sh` was run on a sample log containing ANSI codes, and on a missing log.
- `pick-simulator.py` was run offline against mocked `showdestinations` and `simctl` output. It
  skips placeholders and ineligible destinations, orders OS versions numerically (18.10 > 18.6),
  and skips runtimes newer than the SDK.
- `scripts/ci-status.sh` was run against the real repo. Output: "workflow 'ci.yml' not found on
  GitHub (not pushed yet?)… No workflow runs found for branch 'main'", exit 4. It was also run
  against public repos:
  - `-R actions/checkout -w all main`: run, job and notice annotation printed, exit 0.
  - `-R actions/setup-python -r 40998164002`: a failed run; the failed job and step were listed,
    exit 1.
- Geometry expectations were checked against a line-by-line Python port of `Geometry.swift`. All
  asserted values hold, and the composition check holds to 1e-12.
- All committed files are LF in the index (`git ls-files --eol`). The scripts are mode 100755.

## Not verified until CI runs

- Any Swift compile. The tests are carefully written but have never been compiled.
- Simulator selection on the real image, xcbeautify annotation output, and whether
  `AlignKit-Package` is the scheme name on Xcode 16.4.
- Whether the `swift:5.10-jammy` Linux build passes.
- **D-011 test on this branch alone**: my worktree still has the old `airPodsDefault`
  (forward `(1,0,0)`), so `testAirPodsDefaultAxesCrossProductPointsDown` fails here (cross product
  `(0,0,1)`). It is expected to pass once merged with main's D-011 change.

## Risks / notes

- **Rate limit incident:** while testing `ci-status.sh` on a 100-job public run, I used up this
  machine's unauthenticated GitHub API quota (60/hour) for a while; `/rate_limit` showed 0/60. I
  fixed the script:
  - it checks `/rate_limit` first (that call is free);
  - it fetches annotations for at most 10 jobs (beyond that, only unsuccessful jobs; `-A` for all);
  - it stops at the first 403/429;
  - `-N` skips annotations.
  This repo's CI costs about 8 requests per call.
- GitHub caps annotations at 10 errors and 10 warnings per step (50 per job). The log-tail
  annotation is one of them.
- `push` and `pull_request` both run for same-repo PR branches, so runs are duplicated. This is
  acceptable on free public-repo minutes.
- `.gitattributes`: existing working-tree files in other checkouts are CRLF (autocrlf) with an LF
  index. After the merge, git may list them as modified until they are checked out again. Running
  `git add --renormalize .` is a no-op for the index.
- Privacy: the app needs a `PrivacyInfo.xcprivacy` declaring UserDefaults (`CA92.1`) and
  SystemBootTime (`35F9.1`, because of `systemUptime`). This is not yet on the task board.

## Requirements for other agents (from CI)

- Frontend: `ios/project.yml` with `name: Align` and a shared scheme `Align` that includes the
  app test target (AlignAppTests). Otherwise `xcodebuild test` fails with "not configured for
  the test action".
- Algorithm: `analytics/requirements.txt` and pytest-discoverable `test_*.py` under
  `analytics/experiments`.

## Proposed contract change

None required. Optional: give `PostureConfiguration` a tolerant decoder (defaults for missing
keys) before adding fields, so stored settings survive upgrades (privacy-review R-12).
