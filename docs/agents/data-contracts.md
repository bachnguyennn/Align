# Data contracts

Owner: Lead Architect (local persistence). Version: v1. Phase 2 sync schemas will be agreed by the
Backend and Data agents and added here.

## Local persistence (SwiftData, implemented by the Frontend agent)

### MonitoringSession

| Field | Type | Notes |
|---|---|---|
| id | UUID | primary key (`session_id` in sync API) |
| startedAt | Date | |
| endedAt | Date? | nil while active |
| monitoredDurationSeconds | Double | time streaming, calibrated and not paused |
| withinThresholdSeconds | Double | time in `.neutral` or `.deviating` |
| sustainedDeviationSeconds | Double | time in `.sustainedTilt` |
| reminderCount | Int | |
| calibrationVersion | Int | `NeutralBaseline.version` used |
| sensorAvailabilityStatus | String | `real`, `mock`, or `unavailable` |
| events | [PostureEvent] | cascade delete |

### PostureEvent (one per `PostureEpisode`)

| Field | Type | Notes |
|---|---|---|
| id | UUID | |
| session | MonitoringSession | |
| startedAt / endedAt | Date | converted from monotonic timestamps |
| deviationType | String | `TiltDirection.rawValue` |
| durationSeconds | Double | |
| peakDeviationDegrees | Double | |
| reminderTriggered | Bool | |

### DailySummary (computed, not stored)

`date`, `totalMonitoredMinutes`, `withinThresholdMinutes`, `sustainedDeviationMinutes`,
`reminderCount`, aggregated from sessions by local calendar day (a session spanning midnight is
attributed to its start day in v1).

### Settings (UserDefaults)

`PostureConfiguration` (JSON), sensitivity preset, reminders enabled, sound and haptics,
demo-mode (mock sensor) flag, stored `NeutralBaseline` (JSON).

## Privacy rules

- No raw `MotionSample` data is persisted by default. A developer-only motion recording for
  fixtures may exist behind an explicit toggle and stays on device.
- The user can delete all sessions and the baseline from Privacy & Data.
