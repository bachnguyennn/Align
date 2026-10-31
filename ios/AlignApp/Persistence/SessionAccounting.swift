import Foundation
import AlignCore

/// Accumulates session time from posture updates. Pure value type so it can be unit-tested
/// without sensors, SwiftData or the main actor.
///
/// Each interval between two consecutive sample updates is attributed to the state held at the
/// *start* of the interval (the previous update's state). Steps are capped at `maxStep`
/// (`PostureConfiguration.maxSampleGap`) so a stalled stream cannot inflate durations.
struct SessionAccumulator: Equatable {
    /// Time streaming, calibrated and not paused (`.neutral`, `.deviating`, `.sustainedTilt`).
    private(set) var monitoredSeconds: Double = 0
    /// Time in `.neutral` or `.deviating`.
    private(set) var withinThresholdSeconds: Double = 0
    /// Time in `.sustainedTilt`.
    private(set) var sustainedDeviationSeconds: Double = 0
    /// Reminders actually delivered during the session.
    private(set) var reminderCount: Int = 0

    private var lastTimestamp: TimeInterval?
    private var lastState: PostureState?

    init() {}

    /// Records the state reported by a sample update at `timestamp` (monotonic seconds).
    mutating func record(state: PostureState, at timestamp: TimeInterval, maxStep: TimeInterval) {
        if let previousTimestamp = lastTimestamp, let previousState = lastState {
            let delta = timestamp - previousTimestamp
            if delta < 0 {
                // Out-of-order sample: ignore it and keep the later reference point.
                return
            }
            let step = min(delta, max(0, maxStep))
            if step > 0 {
                switch previousState {
                case .neutral, .deviating:
                    withinThresholdSeconds += step
                    monitoredSeconds += step
                case .sustainedTilt:
                    sustainedDeviationSeconds += step
                    monitoredSeconds += step
                case .unavailable, .needsCalibration, .calibrating:
                    break
                }
            }
        }
        lastTimestamp = timestamp
        lastState = state
    }

    /// Forgets the previous sample so the next one starts a new interval. Call on pause,
    /// disconnect or any monitor interrupt.
    mutating func breakContinuity() {
        lastTimestamp = nil
        lastState = nil
    }

    mutating func recordReminder() {
        reminderCount += 1
    }

    /// Share of monitored time spent within the thresholds, or nil before any monitored time.
    var withinThresholdFraction: Double? {
        guard monitoredSeconds > 0 else { return nil }
        return withinThresholdSeconds / monitoredSeconds
    }
}

/// Converts monotonic sample timestamps (seconds since boot, `CMLogItem.timestamp` /
/// `ProcessInfo.systemUptime` base) to wall-clock dates, as described in architecture.md.
struct MonotonicClock: Equatable {
    var referenceUptime: TimeInterval
    var referenceDate: Date

    init(referenceUptime: TimeInterval, referenceDate: Date) {
        self.referenceUptime = referenceUptime
        self.referenceDate = referenceDate
    }

    /// A clock anchored at the current instant.
    static func now() -> MonotonicClock {
        MonotonicClock(referenceUptime: ProcessInfo.processInfo.systemUptime, referenceDate: Date())
    }

    func date(forUptime timestamp: TimeInterval) -> Date {
        referenceDate.addingTimeInterval(timestamp - referenceUptime)
    }
}

/// Value snapshot of a stored session, used for analytics so the aggregation stays pure.
struct SessionRecord: Equatable {
    var startedAt: Date
    var monitoredSeconds: Double
    var withinThresholdSeconds: Double
    var sustainedDeviationSeconds: Double
    var reminderCount: Int
}

/// Computed per-day summary (data-contracts.md). Not stored.
struct DailySummary: Equatable, Identifiable {
    /// Start of the local calendar day.
    var date: Date
    var totalMonitoredMinutes: Double
    var withinThresholdMinutes: Double
    var sustainedDeviationMinutes: Double
    var reminderCount: Int

    var id: Date { date }

    init(date: Date, totalMonitoredMinutes: Double = 0, withinThresholdMinutes: Double = 0, sustainedDeviationMinutes: Double = 0, reminderCount: Int = 0) {
        self.date = date
        self.totalMonitoredMinutes = totalMonitoredMinutes
        self.withinThresholdMinutes = withinThresholdMinutes
        self.sustainedDeviationMinutes = sustainedDeviationMinutes
        self.reminderCount = reminderCount
    }
}

enum DailySummaryBuilder {
    /// One summary per calendar day for the `days` days ending on `endDate`'s day, oldest first.
    /// Days without sessions are included with zeros. A session is attributed to the day it
    /// started on (v1 rule for sessions spanning midnight).
    static func summaries(from records: [SessionRecord], days: Int, endingOn endDate: Date, calendar: Calendar) -> [DailySummary] {
        guard days > 0 else { return [] }
        let lastDay = calendar.startOfDay(for: endDate)
        var dayStarts: [Date] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            if let day = calendar.date(byAdding: .day, value: -offset, to: lastDay) {
                dayStarts.append(calendar.startOfDay(for: day))
            }
        }

        var buckets: [Date: DailySummary] = [:]
        for day in dayStarts {
            buckets[day] = DailySummary(date: day)
        }
        for record in records {
            let day = calendar.startOfDay(for: record.startedAt)
            guard var summary = buckets[day] else { continue }
            summary.totalMonitoredMinutes += record.monitoredSeconds / 60
            summary.withinThresholdMinutes += record.withinThresholdSeconds / 60
            summary.sustainedDeviationMinutes += record.sustainedDeviationSeconds / 60
            summary.reminderCount += record.reminderCount
            buckets[day] = summary
        }
        return dayStarts.compactMap { buckets[$0] }
    }
}
