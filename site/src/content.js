// Everything the page states as fact, with the repo file it comes from.

export const profile = {
  name: 'Bach Nguyen',
  github: 'https://github.com/bachnguyennn',
  repo: 'https://github.com/bachnguyennn/FixMySpine',
  // Leave empty to hide the link in the footer.
  linkedin: '',
  email: '',
  resume: '',
};

export const file = (path) => `${profile.repo}/blob/main/${path}`;

// The first hardware report lives on its own branch until it is merged.
export const hardwareReport = `${profile.repo}/blob/hardware-test-2026-10-31/docs/agents/reports/hardware-test-2026-10-31.md`;

// docs/agents/integration-log.md, CI run 41249672959 (all jobs green); the last row is this folder's `npm test`.
export const suites = [
  { count: 301, name: 'Java reference', command: './mvnw verify', covers: 'Reference algorithm, fixture replay, motion generator, evaluation', path: 'analytics/align-tools' },
  { count: 164, name: 'Swift package', command: 'swift test', covers: 'Core types, sensors, posture detection, fixture replay', path: 'ios/AlignKit/Tests' },
  { count: 57, name: 'iOS app', command: 'xcodebuild test', covers: 'Session accounting, settings, sample watchdog, motion recording', path: 'ios/AlignAppTests' },
  { count: 154, name: 'Sync server', command: './mvnw verify', covers: 'Device auth, uploads, isolation between devices, pagination, request limits', path: 'server' },
  { count: 20, name: 'This page', command: 'npm test', covers: 'The JavaScript port against the same 14 fixtures, and the simulation', path: 'site/src' },
];

// analytics/align-tools/results/evaluation.md, "Glance length vs reminder".
export const glances = [
  { seconds: 5, reminded: 0 }, { seconds: 10, reminded: 0 }, { seconds: 20, reminded: 0 }, { seconds: 29, reminded: 0 },
  { seconds: 31, reminded: 20 }, { seconds: 32, reminded: 20 }, { seconds: 40, reminded: 20 },
];

// Same file, "Flicker near threshold": mean entries into `deviating` per 60 s hold at exactly 15°.
export const flicker = [
  { label: 'No smoothing, no hysteresis', value: 53.6 },
  { label: 'Smoothing only (0.5 s)', value: 9.9 },
  { label: 'Hysteresis only (3°)', value: 1.2 },
  { label: 'Both, as shipped', value: 1.0, shipped: true },
];

// Same file, "Detection latency (default configuration)".
export const latency = [
  { scenario: 'Gradual forward slouch', once: '20 / 20', delay: '0.58 s' },
  { scenario: 'Right ear to shoulder', once: '20 / 20', delay: '0.56 s' },
  { scenario: 'Looking up', once: '20 / 20', delay: '0.53 s' },
];

// docs/agents/decisions.md.
export const decisions = [
  {
    id: 'D-005',
    title: 'Tilt comes from gravity, not Euler angles',
    body: 'Tilt is the rotation between the calibrated gravity direction and the current one, both in the head’s own frame. Turning your head leaves gravity where it was, so a head turn can never count as a tilt. There is no gimbal lock and no angle wrap, and a stored calibration stays valid between sessions.',
    path: 'ios/AlignKit/Sources/PostureDetection/TiltEstimator.swift',
  },
  {
    id: 'D-002',
    title: 'The detection logic is a pure Swift package',
    body: 'The pipeline imports neither Core Motion nor UIKit. It runs under swift test on macOS and Linux and can be replayed from fixture files, so the logic is tested without a phone or a pair of AirPods.',
    path: 'ios/AlignKit/Package.swift',
  },
  {
    id: 'D-015',
    title: 'A Java reference is the executable specification',
    body: 'The algorithm exists twice. The Java version records its exact output for each of 14 shared motion fixtures. The Swift version must reproduce the same reminders, episodes and calibration results, within one sample period and 0.05°.',
    path: 'shared/fixtures/README.md',
  },
  {
    id: 'D-020',
    title: 'Calibration forgives a fidget but rejects a slow slouch',
    body: 'The first rule failed calibration if any sample strayed 5° from the mean, so one twitch ruined it. Now 90% of samples must be within 5°. That alone let a slow 10° slouch through in 11 of 20 runs and skewed the baseline by about 4.4°, so a second check compares the first and last two seconds and fails on more than 3° of drift.',
    path: 'ios/AlignKit/Sources/PostureDetection/CalibrationService.swift',
  },
  {
    id: 'D-017',
    title: 'One nod teaches the app which way is forward',
    body: 'An earbud sits at a slightly different angle in every ear, which leaks forward tilt into the sideways reading. After calibrating, the user nods once and the app fits the forward axis to that motion. Nodding up works as well as down, and a sideways tilt is rejected.',
    path: 'ios/AlignKit/Sources/PostureDetection/AxisCalibrationService.swift',
  },
  {
    id: 'D-010',
    title: 'Monitoring runs only while the app is open',
    body: 'iOS has no background mode for headphone motion. Keeping audio alive just to keep sensing risks App Review rejection, so the session pauses when the app leaves the foreground and resumes when it returns.',
    path: 'docs/research/airpods-motion-feasibility.md',
  },
  {
    id: 'D-007',
    title: 'Raw motion is never stored',
    body: 'Samples are processed in memory. Only a sustained tilt is saved, as a start, an end, a direction and a peak angle. The app has no account, no network code and no third-party SDK. The one exception is a diagnostic recording that the user starts and shares by hand.',
    path: 'docs/research/privacy-review.md',
  },
];

// docs/agents/reports/hardware-test-2026-10-31.md, "Axis check".
export const axisCheck = [
  { move: 'Chin down', expected: 'Forward +', forward: '+58', lateral: '−1.6' },
  { move: 'Look up', expected: 'Forward −', forward: '−76', lateral: '+5' },
  { move: 'Right ear down', expected: 'Sideways +', forward: '−4', lateral: '+23' },
  { move: 'Left ear down', expected: 'Sideways −', forward: '+37', lateral: '−50' },
  { move: 'Turn left', expected: 'Both near 0', forward: '−19', lateral: '−11' },
  { move: 'Turn right', expected: 'Both near 0', forward: '−18', lateral: '+3' },
];

export const findings = [
  {
    title: 'Calibration has no settle period',
    body: 'Collection starts on the first sample after the tap, while the user is still looking down at the phone. Raising the head then failed the 5° spread limit every time. Calibration now tolerates a brief fidget, but there is still no countdown before samples are collected.',
  },
  {
    title: 'Readings shift when the left earbud takes over',
    body: 'The only cross-axis leakage, +37° forward on a sideways tilt, happened after the stream switched buds. Hypothesis, not yet verified: the two buds report gravity in slightly different frames. The guided nod added since is meant to remove this kind of leakage.',
  },
  {
    title: 'Head turns move the forward reading by about −19°',
    body: 'The test plan expects under 5°. It stays below the 20° backward limit, so it should not cause a reminder by itself. To be rechecked while watching for pitch.',
  },
];

export const stack = [
  { area: 'App', items: 'Swift, SwiftUI, Observation, SwiftData, Swift Charts, Core Motion' },
  { area: 'Tests', items: 'XCTest, JUnit 5, Vitest' },
  { area: 'Reference tools', items: 'Java 21, Maven' },
  { area: 'Sync server', items: 'Java 21, Spring Boot, JPA, Flyway, PostgreSQL. Built and tested, not deployed, not yet used by the app' },
  { area: 'Build and CI', items: 'XcodeGen, GitHub Actions on macOS and Linux runners' },
  { area: 'This page', items: 'React, Vite, Canvas' },
];
