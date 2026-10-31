import SwiftUI
import SwiftData
import Charts
import AlignCore

/// Session history and 7-day analytics (F-08). Everything is computed on device.
@MainActor
struct HistoryView: View {
    @Query(sort: \MonitoringSession.startedAt, order: .reverse) private var sessions: [MonitoringSession]

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No sessions yet",
                        systemImage: "chart.bar",
                        description: Text("Start monitoring from Home. Your sessions and trends will appear here.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        WeeklyCharts(summaries: weeklySummaries)
                    } header: {
                        Text("Last 7 days")
                    }
                    Section {
                        ForEach(sessions) { session in
                            NavigationLink {
                                SessionDetailView(session: session)
                            } label: {
                                SessionRow(session: session)
                            }
                        }
                    } header: {
                        Text("Sessions")
                    }
                }
            }
            .navigationTitle("History")
        }
    }

    private var weeklySummaries: [DailySummary] {
        DailySummaryBuilder.summaries(
            from: sessions.map { $0.record },
            days: 7,
            endingOn: Date(),
            calendar: Calendar.current
        )
    }
}

/// Bar charts: monitored vs. sustained-tilt minutes per day, and reminders per day.
struct WeeklyCharts: View {
    let summaries: [DailySummary]

    private struct MinutesPoint: Identifiable {
        let day: Date
        let series: String
        let minutes: Double
        var id: String { "\(day.timeIntervalSinceReferenceDate)-\(series)" }
    }

    private static let monitoredSeries = "Monitored"
    private static let tiltedSeries = "Sustained tilt"

    private var minutesPoints: [MinutesPoint] {
        var points: [MinutesPoint] = []
        for summary in summaries {
            points.append(MinutesPoint(day: summary.date, series: WeeklyCharts.monitoredSeries, minutes: summary.totalMonitoredMinutes))
            points.append(MinutesPoint(day: summary.date, series: WeeklyCharts.tiltedSeries, minutes: summary.sustainedDeviationMinutes))
        }
        return points
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Minutes per day")
                .font(.subheadline.weight(.semibold))
            Chart {
                ForEach(minutesPoints) { point in
                    BarMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value("Minutes", point.minutes)
                    )
                    .foregroundStyle(by: .value("Measure", point.series))
                    .position(by: .value("Measure", point.series))
                    .accessibilityLabel(Text("\(point.day.formatted(.dateTime.weekday(.wide))), \(point.series)"))
                    .accessibilityValue(Text("\(Int(point.minutes.rounded())) minutes"))
                }
            }
            .chartForegroundStyleScale([
                WeeklyCharts.monitoredSeries: Theme.accent,
                WeeklyCharts.tiltedSeries: Theme.caution,
            ])
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            }
            .frame(height: 180)

            Text("Reminders per day")
                .font(.subheadline.weight(.semibold))
            Chart {
                ForEach(summaries) { summary in
                    BarMark(
                        x: .value("Day", summary.date, unit: .day),
                        y: .value("Reminders", summary.reminderCount)
                    )
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel(Text(summary.date.formatted(.dateTime.weekday(.wide))))
                    .accessibilityValue(Text("\(summary.reminderCount) reminders"))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3))
            }
            .frame(height: 120)

            Text(weekSummaryText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, Theme.Spacing.s)
    }

    private var weekSummaryText: String {
        let monitored = summaries.reduce(0) { $0 + $1.totalMonitoredMinutes }
        let tilted = summaries.reduce(0) { $0 + $1.sustainedDeviationMinutes }
        let reminders = summaries.reduce(0) { $0 + $1.reminderCount }
        return "This week: \(Format.duration(monitored * 60)) monitored, \(Format.duration(tilted * 60)) in a sustained tilt, \(reminders) reminders."
    }
}

struct SessionRow: View {
    let session: MonitoringSession

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.body.weight(.medium))
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts = ["\(Format.duration(session.monitoredDurationSeconds)) monitored"]
        if session.monitoredDurationSeconds > 0 {
            parts.append("\(Format.percent(session.withinThresholdSeconds / session.monitoredDurationSeconds)) in range")
        }
        parts.append(session.reminderCount == 1 ? "1 reminder" : "\(session.reminderCount) reminders")
        if session.endedAt == nil {
            parts.append("in progress")
        }
        return parts.joined(separator: " · ")
    }
}

struct SessionDetailView: View {
    let session: MonitoringSession

    var body: some View {
        List {
            Section("Session") {
                LabeledContent("Started", value: session.startedAt.formatted(date: .abbreviated, time: .shortened))
                if let ended = session.endedAt {
                    LabeledContent("Ended", value: ended.formatted(date: .omitted, time: .shortened))
                } else {
                    LabeledContent("Ended", value: "In progress")
                }
                LabeledContent("Monitored", value: Format.duration(session.monitoredDurationSeconds))
                LabeledContent("Within range", value: Format.duration(session.withinThresholdSeconds))
                LabeledContent("Sustained tilt", value: Format.duration(session.sustainedDeviationSeconds))
                LabeledContent("Reminders", value: "\(session.reminderCount)")
                LabeledContent("Sensor", value: sensorText)
                LabeledContent("Calibration", value: "#\(session.calibrationVersion)")
            }
            Section {
                if sortedEvents.isEmpty {
                    Text("No sustained tilts in this session.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedEvents) { event in
                        EventRow(event: event)
                    }
                }
            } header: {
                Text("Sustained tilts")
            } footer: {
                Text("Only tilts that lasted past your hold time are recorded. Raw motion data is never stored.")
            }
        }
        .navigationTitle(session.startedAt.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sortedEvents: [PostureEvent] {
        session.events.sorted { $0.startedAt < $1.startedAt }
    }

    private var sensorText: String {
        switch SensorAvailabilityStatus(rawValue: session.sensorAvailabilityStatus) {
        case .real: return "AirPods"
        case .mock: return "Demo sensor"
        case .unavailable: return "Unavailable"
        case .none: return session.sensorAvailabilityStatus
        }
    }
}

struct EventRow: View {
    let event: PostureEvent

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(directionTitle) · peak \(Format.degrees(event.peakDeviationDegrees))")
                    .font(.body)
                Text("\(event.startedAt.formatted(date: .omitted, time: .shortened)) · \(Format.duration(event.durationSeconds))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if event.reminderTriggered {
                Image(systemName: "bell")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Reminder sent")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var directionTitle: String {
        TiltDirection(rawValue: event.deviationType)?.title ?? event.deviationType.capitalized
    }
}
