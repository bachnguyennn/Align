# API contracts — Align sync server v1

Owner: Backend agent (D-014, D-018). Status: **v1, implemented in `server/`**, not deployed
anywhere. The app is still offline-first and does not call this API yet (the opt-in sync toggle
is a later task). Payload fields mirror [`data-contracts.md`](data-contracts.md).

Items marked **[proposal]** are not derivable from `data-contracts.md` or the decision log and
need the Lead's sign-off; they are implemented as written so the server is testable.

## 1. Principles

- **No raw motion, ever.** No endpoint accepts `MotionSample`s, gravity or attitude vectors,
  sample streams or the calibration baseline. Unknown JSON fields are rejected (400), so a client
  cannot slip extra data in.
- **Anonymous devices** (D-018): no accounts, email, Apple ID, device name or hardware id.
- **Offline-safe uploads**: every write is an idempotent upsert keyed by the client's UUIDs, so
  a retry after a lost response is harmless.
- **Isolation**: a device sees and changes only its own data. Client UUIDs are scoped per device
  (see 4.1), so no response ever reveals whether another device used an id.
- **Erase is real**: `DELETE /api/v1/devices/me` removes every row for the device.

## 2. Conventions

| Topic | Rule |
|---|---|
| Base path | `/api/v1` |
| Media type | Requests with a body: `Content-Type: application/json` (else 415). Responses: `application/json`, errors `application/problem+json`. UTF-8. |
| Auth | `Authorization: Bearer <token>` on every endpoint except `POST /devices` and `GET /health`. Token = 32 random bytes, base64url without padding (43 chars `[A-Za-z0-9_-]`). The scheme name is case-insensitive, the token is not. |
| Timestamps | RFC 3339 / ISO 8601 strings, `Z` or an offset (`2026-10-31T08:00:00Z`, `2026-10-31T10:00:00.25+02:00`). Fractional seconds optional; stored with **microsecond** precision (extra digits are truncated, so a re-upload with nanoseconds still compares equal). Responses are always UTC with `Z`. In query strings, encode `+` as `%2B` or use `Z`. |
| Accepted time window | Every timestamp must be ≥ `2020-01-01T00:00:00Z` and ≤ server time + 24 h (clock skew). **[proposal]** |
| Dates | `YYYY-MM-DD` (local calendar dates, only in the summary endpoint). |
| Durations | Seconds as JSON numbers (doubles), like the app. Integers are accepted where a number is expected. |
| Degrees | Degrees as JSON numbers. |
| Strict JSON | Rejected with 400: unknown fields, duplicate keys, trailing content, `NaN`/`Infinity`, a string where a number/boolean is expected (`"2"`), a fraction for an integer (`2.5`), a number where a string is expected. |
| Server fields | `createdAt` / `updatedAt` are server times (UTC), only in responses. Clients must not send them (unknown field → 400). |
| Caching | All responses carry `Cache-Control: no-cache, no-store, max-age=0, must-revalidate`. |

## 3. Errors (RFC 9457 problem details)

Every error is `application/problem+json`:

```json
{
  "type": "https://github.com/bachnguyennn/FixMySpine/blob/main/docs/agents/api-contracts.md#validation-failed",
  "title": "Validation failed",
  "status": 422,
  "detail": "The request body has invalid fields.",
  "instance": "/api/v1/sessions/6f1c…",
  "errors": [ { "field": "endedAt", "message": "must not be before startedAt" } ]
}
```

`errors` is present only for `validation-failed`; `field` is a JSON path (`events[2].startedAt`,
empty for whole-object rules). **Details never echo submitted values.**

#### problem-types

The `type` URI is this document plus one of the anchors below. **[proposal]** (any stable URI works;
these resolve to documentation).

| Anchor / slug | Status | When |
|---|---|---|
| `malformed-request` | 400 | Body missing, not JSON, wrong JSON type, unknown field, duplicate key |
| `invalid-parameter` | 400 | Bad or missing path/query parameter (`limit`, `cursor`, `since`, `from`, `to`, `tz`, non-UUID id) |
| `unauthorized` | 401 | Missing, malformed or unknown token. `WWW-Authenticate: Bearer` (missing) or `Bearer error="invalid_token"` |
| `forbidden` | 403 | Not used by v1 endpoints (reserved) |
| `not-found` | 404 | Unknown route, or a session that does not exist **for this device** |
| `method-not-allowed` | 405 | Wrong HTTP method (`Allow` header set) |
| `not-acceptable` | 406 | `Accept` excludes JSON |
| `conflict` | 409 | An event id already belongs to another session of the same device; a write lost a race with a concurrent identical create (retry) |
| `precondition-failed` | 412 | Settings `If-Match` does not match the current version |
| `payload-too-large` | 413 | Body over 512 KiB (Content-Length or streamed) |
| `unsupported-media-type` | 415 | Body not `application/json` |
| `validation-failed` | 422 | Well-formed JSON that breaks a bound, enum or cross-field rule (`errors` lists them) |
| `limit-exceeded` | 422 | A storage limit would be exceeded (events per session, settings size) |
| `precondition-required` | 428 | `PUT /settings` without `If-Match` |
| `internal-error` | 500 | Anything unexpected (no details) |

Choice of 422 vs 400: 400 = the server could not read the request; 422 = it read it and the
values are not acceptable. **[proposal]**

## 4. Endpoints

### 4.0 Summary

| Method | Path | Auth | Purpose |
|---|---|---|---|
| POST | `/api/v1/devices` | none | Register an anonymous device → `{deviceId, token}` |
| GET | `/api/v1/devices/me` | bearer | Who am I (check a stored token) **[proposal]** |
| DELETE | `/api/v1/devices/me` | bearer | Erase the device and all its data |
| PUT | `/api/v1/sessions/{id}` | bearer | Idempotent upsert of one session (client UUID) |
| GET | `/api/v1/sessions/{id}` | bearer | One session with its events **[proposal]** |
| GET | `/api/v1/sessions?since=&limit=&cursor=` | bearer | Page through sessions changed since an instant |
| PUT | `/api/v1/sessions/{id}/events` | bearer | Batch upsert of that session's events (client UUIDs) |
| GET | `/api/v1/analytics/summary?from=&to=&tz=` | bearer | Daily aggregates, computed like the app |
| GET | `/api/v1/settings` | bearer | The settings document + version (ETag) |
| PUT | `/api/v1/settings` | bearer | Replace the settings document (`If-Match` required) |
| GET | `/api/v1/health` | none | Liveness/readiness: `{"status":"UP"}` (Actuator, no details) |

Nothing else is exposed: other Actuator endpoints are disabled, unknown paths are 401 without a
token and 404 with one.

### 4.1 Devices

#### `POST /api/v1/devices`

No body (any body is ignored). Any `Authorization` header is ignored.

`201 Created`, `Location: /api/v1/devices/me`, `Cache-Control: no-store`:

```json
{ "deviceId": "0c5e7a8e-3f0a-4c36-9a59-0e9f5c1d2b11", "token": "q7Hk…43 chars…", "createdAt": "2026-10-31T19:40:00.123456Z" }
```

| Field | Type | Notes |
|---|---|---|
| `deviceId` | UUID string | Server-generated, random (v4). |
| `token` | string, 43 chars | **Returned only here, once.** The server stores only `SHA-256(token)` (hex). Losing it means losing access to the data; the client must keep it in the Keychain. |
| `createdAt` | timestamp | |

There is no token rotation in v1 **[proposal: later `POST /devices/me/token`]**.

#### `GET /api/v1/devices/me`

`200`: `{ "deviceId": "…", "createdAt": "…" }`. Never returns the token.

#### `DELETE /api/v1/devices/me`

Erases, in one transaction: all posture events, all sessions, the settings document and the
device row. The token stops working immediately (any later call → 401). `204 No Content`. A
second call with the same token → 401. Other devices are unaffected.

### 4.2 Sessions

Mirrors `MonitoringSession` (data-contracts.md). **Identity:** the path `{id}` is the client's
`MonitoringSession.id`. Ids are scoped per device: the server key is (device, id). If two devices
upload the same UUID they get two independent rows, and each device's response is exactly what it
would be for a fresh UUID — so the API cannot be used to probe another device's ids. (Requested
behaviour was "another device's id → 404/409 without leaking existence"; with a global id any
answer that differs from a fresh id's answer leaks existence, so v1 scopes ids instead.
**[proposal]**)

#### `PUT /api/v1/sessions/{id}`

Request body (all fields required unless marked optional; no other fields allowed):

| Field | Type | Unit | Bounds / rule |
|---|---|---|---|
| `id` | UUID | — | **Optional**; if present must equal the path id (422). |
| `startedAt` | timestamp | — | In the accepted window. |
| `endedAt` | timestamp or `null` | — | Optional/`null` while the session is active. ≥ `startedAt`; `endedAt − startedAt` ≤ 7 days **[proposal]**. |
| `monitoredDurationSeconds` | number | s | 0 … 604 800 (7 days) **[proposal]** |
| `withinThresholdSeconds` | number | s | 0 … 604 800 |
| `sustainedDeviationSeconds` | number | s | 0 … 604 800 |
| `reminderCount` | integer | count | 0 … 100 000 **[proposal]** |
| `calibrationVersion` | integer | — | ≥ 0 (`NeutralBaseline.version`) |
| `sensorAvailabilityStatus` | string | — | `real` \| `mock` \| `unavailable` |

Cross-field rule: `withinThresholdSeconds + sustainedDeviationSeconds ≤ monitoredDurationSeconds + 0.01`
(the app's `SessionAccumulator` adds every step to `monitored` and to exactly one of the other two,
so they sum to it up to floating-point error). **[proposal]** `monitoredDurationSeconds` is *not*
checked against `endedAt − startedAt` (monotonic vs wall clock may differ slightly).

Semantics (replace the stored copy with the body = last write wins):

| Situation | Status | Effect |
|---|---|---|
| New id for this device | `201 Created`, `Location: /api/v1/sessions/{id}` | Row created; `createdAt = updatedAt = now` |
| Existing, identical body (after µs truncation) | `200 OK` | Nothing changes, `updatedAt` unchanged |
| Existing, different body | `200 OK` | All fields replaced, `updatedAt = now` |
| Invalid | 400 / 422 | Nothing stored |

Response body (all three success cases):

```json
{
  "id": "6f1c2b9e-…", "startedAt": "2026-03-02T08:00:00Z", "endedAt": "2026-03-02T08:30:00Z",
  "monitoredDurationSeconds": 1200.0, "withinThresholdSeconds": 1080.0, "sustainedDeviationSeconds": 120.0,
  "reminderCount": 2, "calibrationVersion": 3, "sensorAvailabilityStatus": "real",
  "createdAt": "2026-10-31T19:41:02.000001Z", "updatedAt": "2026-10-31T19:41:02.000001Z"
}
```

There is no "older snapshot must not overwrite newer" check: the device is the only writer for
its own data and uploads in order. **[proposal: if multi-device sync arrives, add a client
revision or `If-Match` on sessions]**

#### `GET /api/v1/sessions/{id}`

`200`: the session object above plus `"events": [ … ]` (all its events, ordered by `startedAt`,
then `id`; event objects as in 4.3 plus `createdAt`/`updatedAt`). `404 not-found` if this device
has no session with that id (identical for "never existed" and "belongs to another device").

#### `GET /api/v1/sessions?since=&limit=&cursor=`

| Parameter | Type | Default | Rule |
|---|---|---|---|
| `since` | timestamp | none (all) | Return sessions with server `updatedAt ≥ since` (inclusive). |
| `limit` | integer | 50 | 1 … 200 |
| `cursor` | opaque string | none | `nextCursor` from the previous page. Pass the same `since`. |

Order: `updatedAt` ascending, then `id` (keyset pagination; stable under concurrent inserts).
`200`:

```json
{ "items": [ { …session without events… } ], "nextCursor": "djF8MTc2…" }
```

`nextCursor` is `null` on the last page (a page can be full and still be the last one). Clients
must treat the cursor as opaque. A changed event also bumps its session's `updatedAt`, so
"sessions since T" is the complete change set for restore/sync.

Sync recipe **[proposal]**: remember the server time of the newest `updatedAt` seen; next time
call with `since` = that value minus 1 minute (overlap tolerates concurrent commits; duplicates
are harmless because applying a session is idempotent).

### 4.3 Posture events

#### `PUT /api/v1/sessions/{id}/events`

Batch upsert of `PostureEvent`s (one per sustained-tilt episode) of session `{id}` of this
device. The session must exist first (`PUT /sessions/{id}`), else `404`.

```json
{ "events": [
  { "id": "a6c0…", "startedAt": "2026-03-02T08:05:00Z", "endedAt": "2026-03-02T08:05:45Z",
    "deviationType": "forward", "durationSeconds": 45.0, "peakDeviationDegrees": 22.5, "reminderTriggered": true }
] }
```

| Field | Type | Unit | Bounds / rule |
|---|---|---|---|
| `events` | array | — | 1 … 500 items **[proposal]**; ids unique within the batch |
| `id` | UUID | — | Client `PostureEvent.id`; scoped per device like session ids |
| `startedAt`, `endedAt` | timestamp | — | Accepted window; `endedAt ≥ startedAt`; ≤ 24 h apart |
| `deviationType` | string | — | `forward` \| `backward` \| `left` \| `right` (`TiltDirection.rawValue`) |
| `durationSeconds` | number | s | 0 … 86 400 **[proposal]** |
| `peakDeviationDegrees` | number | ° | 0 … 180 **[proposal]** |
| `reminderTriggered` | boolean | — | |

Semantics: each event is created, replaced or left unchanged by id; events of the session that
are not in the batch are kept (it is not a full replacement — there is no event delete in v1
**[proposal]**). The batch is all-or-nothing: any invalid item → 422 and nothing is stored. An
event id that this device already used under a *different* session → `409 conflict`. A session
holds at most 5 000 events → `422 limit-exceeded` **[proposal]**. If anything was created or
updated, the session's `updatedAt` moves to now.

`200 OK`: `{ "created": 2, "updated": 0, "unchanged": 1 }`.

### 4.4 Daily summary

#### `GET /api/v1/analytics/summary?from=YYYY-MM-DD&to=YYYY-MM-DD&tz=<IANA zone>`

All three parameters are required. `from ≤ to`, at most 366 days inclusive. `tz` is an IANA
region id (`Europe/Berlin`, `America/Los_Angeles`) or `UTC`; the client should send
`TimeZone.current.identifier`.

Computed exactly like the app's `DailySummaryBuilder.summaries` in
`ios/AlignApp/Persistence/SessionAccounting.swift`:

1. One entry per local calendar day `from … to` in `tz`, **oldest first; days without sessions
   are included with zeros**.
2. A session belongs to the local day containing its `startedAt` (`calendar.startOfDay(for:
   startedAt)`); **a session crossing midnight counts wholly for its start day** (data-contracts.md
   v1 rule). Days are real local days, so DST days have 23 or 25 hours.
3. Per day: `totalMonitoredMinutes = Σ monitoredDurationSeconds / 60`,
   `withinThresholdMinutes = Σ withinThresholdSeconds / 60`,
   `sustainedDeviationMinutes = Σ sustainedDeviationSeconds / 60`, `reminderCount = Σ reminderCount`.
   Each session's seconds are divided by 60 and then summed, **no rounding**.
4. Active sessions (`endedAt == null`) are included with their current totals, as in the app's
   History view (its `@Query` has no `endedAt` filter).
5. Events do not contribute (the app's summary uses session fields only).

`200`:

```json
{ "from": "2026-03-01", "to": "2026-03-02", "timeZone": "UTC", "days": [
  { "date": "2026-03-01", "totalMonitoredMinutes": 75.0, "withinThresholdMinutes": 65.0,
    "sustainedDeviationMinutes": 10.0, "reminderCount": 1 },
  { "date": "2026-03-02", "totalMonitoredMinutes": 0.0, "withinThresholdMinutes": 0.0,
    "sustainedDeviationMinutes": 0.0, "reminderCount": 0 } ] }
```

`date` is a local date string, not the app's `Date` at local midnight (the client converts it
with its calendar). Errors: `400 invalid-parameter` for missing/invalid dates, `to < from`,
range > 366 days, unknown zone.

### 4.5 Settings

One JSON document per device: the app's `AppSettings` toggles plus the user-tunable
`PostureConfiguration` fields (same names and units). Every field is optional; missing = app
default. **Deliberately excluded** **[proposal]**: `axes` (the app always uses the package
default, D-011 — sending it is a 400), the `NeutralBaseline` and learned axes (per earbud fit,
D-017; derived from motion), and the sensitivity preset (derived from the thresholds, D-013).

| Field | Type | Bounds **[proposal]** |
|---|---|---|
| `remindersEnabled`, `soundEnabled`, `hapticsEnabled`, `demoModeEnabled` | boolean | — |
| `configuration.calibrationDuration` | number, s | 1 … 120 |
| `configuration.calibrationMaxSpreadDegrees` | number, ° | 0.5 … 30 |
| `configuration.calibrationSpreadQuantile` | number | 0.5 … 1 |
| `configuration.minimumCalibrationSamples` | integer | 1 … 100 000 |
| `configuration.forwardThresholdDegrees`, `backwardThresholdDegrees`, `lateralThresholdDegrees` | number, ° | 1 … 90 |
| `configuration.hysteresisDegrees` | number, ° | 0 … 30 |
| `configuration.sustainedDuration` | number, s | 1 … 3 600 |
| `configuration.reminderCooldown` | number, s | 0 … 86 400 |
| `configuration.smoothingTimeConstant` | number, s | 0 … 10 |
| `configuration.maxProcessingRateHz` | number, Hz | 1 … 1 000 (absent = every sample) |
| `configuration.maxSampleGap` | number, s | 0.01 … 60 |
| `configuration.axisCalibrationDuration` | number, s | 1 … 120 |
| `configuration.axisCalibrationMinimumNodDegrees` | number, ° | 1 … 90 |
| `configuration.axisCalibrationMaxYawDegrees` | number, ° | 0 … 90 |
| `configuration.axisCalibrationMaxOffAxisRatio` | number | 0 … 10 |

Stored size limit: 16 KiB of canonical JSON (`422 limit-exceeded`).

#### `GET /api/v1/settings`

`200`, `ETag: "<version>"`:

```json
{ "version": 3, "updatedAt": "2026-10-31T19:45:00Z", "settings": { "soundEnabled": false, "configuration": { "forwardThresholdDegrees": 12.0 } } }
```

Before the first write: `{ "version": 0, "updatedAt": null, "settings": {} }`, `ETag: "0"`.
`If-None-Match: "<version>"` → `304 Not Modified`.

#### `PUT /api/v1/settings`

Body `{ "settings": { … } }` (required, replaces the whole document). Optimistic concurrency:

| `If-Match` | Result |
|---|---|
| missing | `428 precondition-required` |
| `"N"` equal to the current version (`"0"` when no document exists) | Written; version becomes N+1 (or stays N if the document is identical) → `200` with the envelope and new `ETag` |
| `"N"` not equal, a weak tag `W/"N"`, or anything unparseable | `412 precondition-failed`, nothing changes |
| `*` | Matches an existing document only (412 if none) |

The comparison and increment happen in one conditional `UPDATE`, so two concurrent writers with
the same `If-Match` cannot both win. On 412 the client GETs, merges and retries.

### 4.6 Health

`GET /api/v1/health` (Spring Boot Actuator): `200 {"status":"UP"}` or `503 {"status":"DOWN"}`
(includes the database check). No component details. No other Actuator endpoint is exposed.

## 5. Limits

| Limit | Value | Error |
|---|---|---|
| Request body | 512 KiB (`ALIGN_MAX_REQUEST_BYTES`) | 413 |
| Events per request | 500 | 422 `validation-failed` |
| Events per session | 5 000 | 422 `limit-exceeded` |
| Page size | default 50, max 200 | 400 |
| Summary range | 366 days | 400 |
| Settings document | 16 KiB | 422 `limit-exceeded` |
| Session length / durations | 7 days | 422 |
| Event length / duration | 24 h | 422 |
| Rate limiting | **none in v1** — see the backend report; needed before any public deployment **[proposal]** | (429 reserved) |

## 6. What the server stores

| Table | Columns | Never stored |
|---|---|---|
| `device` | id, SHA-256(token), createdAt | token, IP, user agent, device name/model, Apple ID |
| `monitoring_session` | the session fields above + device id, createdAt, updatedAt | — |
| `posture_event` | the event fields above + device/session refs, createdAt, updatedAt | raw motion, gravity, attitude |
| `device_settings` | version, canonical JSON document, updatedAt | baseline, axes |

Retention: until the device erases it (`DELETE /devices/me`). No backups, analytics or logs of
payloads exist yet (not deployed). See `docs/research/privacy-review.md` §9.
