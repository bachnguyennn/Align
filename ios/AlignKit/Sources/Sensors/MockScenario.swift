import Foundation

/// Scripted head-motion scenarios played by `MockSensorProvider`.
///
/// Times below are simulated seconds since `start()` (or since the scenario last changed).
/// Timelines that end return to neutral and repeat, so a demo can run indefinitely.
public enum MockScenario: String, CaseIterable, Sendable {
    /// Pose set by `MockSensorProvider.setSimulatedTilt`; small realistic noise.
    case manual
    /// Neutral head with small postural sway and slow left/right head turns.
    case steadyNeutral
    /// Neutral 20 s, drifts to ~25° forward over 10 s, holds 60 s, returns over 5 s.
    /// Repeats every 120 s.
    case gradualForwardSlouch
    /// Every 15 s, a 3–5 s glance to ~30° forward (durations cycle 3, 4, 5 s).
    case briefGlanceDown
    /// Neutral 15 s, tilts to ~20° right over 3 s, holds 45 s, returns over 3 s.
    /// Repeats every 90 s.
    case lateralTilt
    /// Streams 20 s, disconnects for 10 s (`.waitingForHeadphones`), then reconnects and
    /// keeps streaming. The sensor location switches from the left to the right bud.
    case disconnectMidSession
    /// Reports `.unavailable(.motionNotSupported)` and emits no samples.
    case unavailable
    /// Reports `.unavailable(.notAuthorized)` and emits no samples.
    case permissionDenied
}
