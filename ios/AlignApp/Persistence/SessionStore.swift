import Foundation
import SwiftData
import os
import AlignCore

/// Logging categories. Never log raw motion values.
enum Log {
    static let persistence = Logger(subsystem: "com.bachnguyennn.align", category: "persistence")
    static let monitoring = Logger(subsystem: "com.bachnguyennn.align", category: "monitoring")
    static let notifications = Logger(subsystem: "com.bachnguyennn.align", category: "notifications")
}

/// Thin wrapper over the SwiftData main context for session and event writes.
/// Reads for the UI use `@Query` directly.
@MainActor
final class SessionStore {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func startSession(startedAt: Date, calibrationVersion: Int, status: SensorAvailabilityStatus) -> MonitoringSession {
        let session = MonitoringSession(
            startedAt: startedAt,
            calibrationVersion: calibrationVersion,
            sensorAvailabilityStatus: status.rawValue
        )
        context.insert(session)
        save()
        return session
    }

    /// Stores one completed sustained-tilt episode on `session`.
    func addEvent(from episode: PostureEpisode, reminderTriggered: Bool, to session: MonitoringSession, clock: MonotonicClock) {
        let event = PostureEvent(
            startedAt: clock.date(forUptime: episode.startTimestamp),
            endedAt: clock.date(forUptime: episode.endTimestamp),
            deviationType: episode.direction.rawValue,
            durationSeconds: max(0, episode.endTimestamp - episode.startTimestamp),
            peakDeviationDegrees: episode.peakDeviationDegrees,
            reminderTriggered: reminderTriggered
        )
        // Insert first, then link, so both objects live in the same context.
        context.insert(event)
        event.session = session
        save()
    }

    func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            Log.persistence.error("Saving failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Deletes every session and event.
    func deleteAllHistory() {
        do {
            let events = try context.fetch(FetchDescriptor<PostureEvent>())
            for event in events {
                context.delete(event)
            }
            let sessions = try context.fetch(FetchDescriptor<MonitoringSession>())
            for session in sessions {
                context.delete(session)
            }
            try context.save()
        } catch {
            Log.persistence.error("Deleting history failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Closes sessions left open by a crash or a force quit. Their end is estimated as start plus
    /// the monitored time that was last saved.
    func closeUnfinishedSessions() {
        do {
            let sessions = try context.fetch(FetchDescriptor<MonitoringSession>())
            for session in sessions where session.endedAt == nil {
                session.endedAt = session.startedAt.addingTimeInterval(session.monitoredDurationSeconds)
            }
            save()
        } catch {
            Log.persistence.error("Closing unfinished sessions failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
