# Align sync server

Optional Phase 2 backend (D-014, D-018): anonymous device registration, idempotent upload of
session aggregates and sustained-tilt events, daily summaries, and a settings document. The app
stays offline-first and does not use it yet; the server is not deployed anywhere.

Java 21, Spring Boot 3.5.16 (Web, Validation, Data JPA, Security, Actuator), Flyway, PostgreSQL.
API contract: [`docs/agents/api-contracts.md`](../docs/agents/api-contracts.md).

## Run locally

With Docker (server + PostgreSQL 16, both bound to localhost):

```sh
cd server
docker compose up --build
curl -s -X POST localhost:8080/api/v1/devices        # → {"deviceId": "...", "token": "..."}
```

Without Docker, against your own PostgreSQL 16:

```sh
cd server
createdb align                                       # owner/user "align", password "align"
./mvnw spring-boot:run                               # mvnw.cmd in cmd.exe; needs JDK 21 (JAVA_HOME)
```

Flyway creates the schema on startup (`src/main/resources/db/migration`); Hibernate only
validates it.

Example session, with `TOKEN` from the registration:

```sh
curl -s -X PUT localhost:8080/api/v1/sessions/6f1c2b9e-0d5e-4b7a-9a0f-3e2d1c0b9a87 \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"startedAt":"2026-10-30T08:00:00Z","endedAt":"2026-10-30T08:30:00Z","monitoredDurationSeconds":1200,
       "withinThresholdSeconds":1080,"sustainedDeviationSeconds":120,"reminderCount":2,
       "calibrationVersion":3,"sensorAvailabilityStatus":"real"}'
curl -s "localhost:8080/api/v1/analytics/summary?from=2026-10-24&to=2026-10-30&tz=Europe/Berlin" \
  -H "Authorization: Bearer $TOKEN"
```

## Configuration (environment variables)

| Variable | Default (local dev only) | Meaning |
|---|---|---|
| `DATABASE_URL` | `jdbc:postgresql://localhost:5432/align` | JDBC URL (not the `postgres://` form) |
| `DATABASE_USERNAME` | `align` | |
| `DATABASE_PASSWORD` | `align` | Set a real secret in any shared environment |
| `DATABASE_POOL_SIZE` | `10` | Hikari maximum pool size |
| `PORT` | `8080` | HTTP port |
| `ALIGN_MAX_REQUEST_BYTES` | `524288` | Largest request body (413 above it) |

Any Spring property can also be overridden the usual way (`SPRING_…` variables). TLS is
expected to end at a reverse proxy or platform load balancer; the server speaks plain HTTP.

## Test

```sh
cd server
./mvnw -B -ntp verify          # JDK 21; no Docker, no database needed
```

By default the suite runs on in-memory H2 in PostgreSQL mode. To run the same tests against a
real PostgreSQL (CI does this with a `postgres:16` service container):

```sh
ALIGN_TEST_DATABASE_URL=jdbc:postgresql://localhost:5432/align_test \
ALIGN_TEST_DATABASE_USERNAME=align ALIGN_TEST_DATABASE_PASSWORD=align \
ALIGN_TEST_EXPECT_DATABASE=PostgreSQL ./mvnw -B -ntp verify
```

`ALIGN_TEST_EXPECT_DATABASE` makes `DatabaseEngineTest` fail if the suite fell back to H2.

| Test class | Covers |
|---|---|
| `DeviceApiTest` | Registration (token format, only the hash stored), `GET /devices/me`, erase-all and token revocation |
| `AuthenticationTest` | 401 problem+json + `WWW-Authenticate` on every protected route for missing, unknown and malformed tokens; health is public without details; other Actuator endpoints absent; 404/405 problems |
| `SessionApiTest` | Create (201) / identical repeat (200, unchanged) / update (200); open sessions; µs truncation; every bound and cross-field rule (422 with field); malformed JSON variants (400); 415 |
| `EventApiTest` | Batch upsert counts, idempotent retry, partial updates, ordering, 404 for unknown session, 409 for an id reused across sessions, batch limits, per-field validation, raw-motion fields rejected |
| `IsolationTest` | A device cannot read, list, summarize or extend another device's data; reused UUIDs stay independent; settings and erase are per device |
| `PaginationTest` | Keyset pages cover every session once; last page has `nextCursor: null`; `since`; invalid parameters |
| `SummaryApiTest` | Per-day sums with zero days, a session crossing midnight, Los Angeles / Tokyo / UTC attribution, the 25-hour DST day in Berlin, no rounding, range limits |
| `SettingsApiTest` | Version 0 → 1 → 2, stale/weak/malformed `If-Match` → 412, missing → 428, `*`, identical write keeps the version, 304, bounds (422), `axes`/baseline/wrong types rejected (400) |
| `RequestLimitsTest`, `RequestSizeLimitFilterTest` | 413 by Content-Length and while streaming; 500-event batch fits; 5 000 events per session |
| `NoSecretsInLogsTest` | Tokens and payload values never appear in the log, including on error paths |
| `DatabaseEngineTest` | Which database ran; all Flyway migrations applied |
| `TokenServiceTest`, `PageCursorTest` | Token generation/hashing; cursor encoding |

## API overview

| Method | Path | Semantics |
|---|---|---|
| POST | `/api/v1/devices` | Register; returns `deviceId` and the bearer token (shown once) |
| GET | `/api/v1/devices/me` | The calling device |
| DELETE | `/api/v1/devices/me` | Erase the device and all its data; the token stops working |
| PUT | `/api/v1/sessions/{id}` | Idempotent upsert by client UUID (201 / 200) |
| GET | `/api/v1/sessions/{id}` | One session with its events |
| GET | `/api/v1/sessions?since=&limit=&cursor=` | Sessions changed since an instant, keyset-paginated |
| PUT | `/api/v1/sessions/{id}/events` | Batch upsert of the session's events (≤ 500) |
| GET | `/api/v1/analytics/summary?from=&to=&tz=` | Daily totals computed like the app |
| GET / PUT | `/api/v1/settings` | Settings document; PUT needs `If-Match: "<version>"` |
| GET | `/api/v1/health` | `{"status":"UP"}` |

Errors are RFC 9457 `application/problem+json`. Full details, bounds and limits are in the
contract.

## Security notes

- **Tokens**: 32 bytes from `SecureRandom`, base64url (43 chars). Only `SHA-256(token)` is stored;
  lookup is by hash and the stored hash is compared with `MessageDigest.isEqual` (constant time).
  The token is returned once, with `Cache-Control: no-store`.
- **Ownership**: every query is keyed by the authenticated device id; client UUIDs are scoped per
  device, so no response reveals another device's data or ids (tested in `IsolationTest`).
- **Input**: strict JSON (unknown fields, coercions, duplicate keys and trailing data rejected),
  Bean Validation bounds plus cross-field rules, 512 KiB body limit (also enforced on streamed
  bodies), batch and per-session limits. No endpoint accepts raw motion.
- **Logging**: no request/response bodies, headers or SQL parameters are logged; error details
  never echo submitted values; unexpected exceptions are logged by class and location only. Keep
  `org.springframework.web`, `org.hibernate.SQL` and `org.hibernate.orm.jdbc.bind` at INFO/WARN.
- **Surface**: stateless (no cookies, sessions or CSRF), no form/basic login, no default user;
  Actuator exposes only `health` without details; the container runs as a non-root user.
- **Not yet done** (needed before a public deployment): rate limiting (especially for
  `POST /devices`), TLS termination and HSTS at the edge, database backups and their retention,
  monitoring. See `docs/agents/reports/backend.md`.
