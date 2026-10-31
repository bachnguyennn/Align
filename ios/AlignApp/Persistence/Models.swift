import Foundation
import SwiftData

/// `MonitoringSession.sensorAvailabilityStatus` values (data-contracts.md).
enum SensorAvailabilityStatus: String {
    case real
    case mock
    case unavailable
}

/// One monitoring session. Field names follow docs/agents/data-contracts.md.
@Model
final class MonitoringSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    /// Nil while the session is active.
    var endedAt: Date?
    var monitoredDurationSeconds: Double
    var withinThresholdSeconds: Double
    var sustainedDeviationSeconds: Double
    var reminderCount: Int
    var calibrationVersion: Int
    /// `real`, `mock` or `unavailable`.
    var sensorAvailabilityStatus: String
    @Relationship(deleteRule: .cascade, inverse: \PostureEvent.session)
    var events: [PostureEvent] = []

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        monitoredDurationSeconds: Double = 0,
        withinThresholdSeconds: Double = 0,
        sustainedDeviationSeconds: Double = 0,
        reminderCount: Int = 0,
        calibrationVersion: Int,
        sensorAvailabilityStatus: String
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.monitoredDurationSeconds = monitoredDurationSeconds
        self.withinThresholdSeconds = withinThresholdSeconds
        self.sustainedDeviationSeconds = sustainedDeviationSeconds
        self.reminderCount = reminderCount
        self.calibrationVersion = calibrationVersion
        self.sensorAvailabilityStatus = sensorAvailabilityStatus
    }

    var record: SessionRecord {
        SessionRecord(
            startedAt: startedAt,
            monitoredSeconds: monitoredDurationSeconds,
            withinThresholdSeconds: withinThresholdSeconds,
            sustainedDeviationSeconds: sustainedDeviationSeconds,
            reminderCount: reminderCount
        )
    }
}

/// One sustained-tilt episode (`PostureEpisode`) within a session.
@Model
final class PostureEvent {
    @Attribute(.unique) var id: UUID
    var session: MonitoringSession?
    var startedAt: Date
    var endedAt: Date
    /// `TiltDirection.rawValue`.
    var deviationType: String
    var durationSeconds: Double
    var peakDeviationDegrees: Double
    var reminderTriggered: Bool

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date,
        deviationType: String,
        durationSeconds: Double,
        peakDeviationDegrees: Double,
        reminderTriggered: Bool
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.deviationType = deviationType
        self.durationSeconds = durationSeconds
        self.peakDeviationDegrees = peakDeviationDegrees
        self.reminderTriggered = reminderTriggered
    }
}
