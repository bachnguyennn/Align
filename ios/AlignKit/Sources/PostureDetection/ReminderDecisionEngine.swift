import Foundation
import AlignCore

/// Reminder cooldown policy. `PostureMonitor` calls `evaluate` once per episode, on the update
/// where the tilt becomes sustained, so there is never more than one reminder per episode.
/// A reminder is given if none was given yet, or at least `cooldown` seconds have passed since
/// the last one. A timestamp earlier than the last reminder (clock base changed) also allows one.
/// Mirrors `align_reference/reminder.py`.
public struct ReminderDecisionEngine: Sendable {
    public private(set) var lastReminderTimestamp: TimeInterval?

    public init() {}

    public mutating func reset() {
        lastReminderTimestamp = nil
    }

    public mutating func evaluate(
        timestamp: TimeInterval,
        direction: TiltDirection,
        deviationDegrees: Double,
        sustainedSeconds: Double,
        cooldown: TimeInterval
    ) -> ReminderDecision? {
        if let last = lastReminderTimestamp,
           timestamp >= last,
           timestamp - last + PostureDetectionConstants.timeEpsilon < cooldown {
            return nil
        }
        lastReminderTimestamp = timestamp
        return ReminderDecision(
            timestamp: timestamp,
            direction: direction,
            deviationDegrees: deviationDegrees,
            sustainedSeconds: sustainedSeconds
        )
    }
}
