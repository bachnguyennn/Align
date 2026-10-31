# Backend agent report — Phase 2 sync server (D-014, D-018)

Date: 2026-10-31. Branch: `worktree-agent-aa8a13ce7579defa0` (fast-forwarded to `main` at
`0af3f4d` first, so D-017/D-018 are included). Not pushed.

## Delivered

| Item | Where |
|---|---|
| Full v1 API contract (endpoints, payloads with types/units/bounds, problem types, auth, idempotency, pagination, summary rules, limits, what is stored) | `docs/agents/api-contracts.md` |
| Spring Boot 3.5.16 server (latest 3.x on Maven Central; 4.x exists but the brief asked for 3.x), Java 21, Maven wrapper 3.9.16 | `server/` |
| Flyway schema `V1__init.sql` (device, monitoring_session, posture_event, device_settings; FKs cascade, CHECK constraints mirror the bounds) | `server/src/main/resources/db/migration` |
| 154 JUnit 5 tests (MockMvc over the whole app incl. filters and security), run without Docker on H2 in PostgreSQL mode | `server/src/test` |
| CI job `server` running the same suite on a `postgres:16` service container | `.github/workflows/ci.yml` |
| Multi-stage non-root `Dockerfile`, `docker-compose.yml` (server + PostgreSQL 16, localhost-only ports) | `server/` |
| Docs: server README, architecture section, root README layout/test rows, test-plan CI row, privacy review §9, `.gitignore` | as listed |

## Test results (real output)

Local, Windows 11, Temurin 21.0.13, `./mvnw -B -ntp clean verify` on H2 2.3.232:

```
[INFO] Tests run: 154, Failures: 0, Errors: 0, Skipped: 0
[INFO] BUILD SUCCESS
```

Per class: AuthenticationTest 34, SessionApiTest 34, SettingsApiTest 23, EventApiTest 17,
SummaryApiTest 14, PaginationTest 10, DeviceApiTest 5, IsolationTest 4, TokenServiceTest 4,
RequestLimitsTest 3, PageCursorTest 2, RequestSizeLimitFilterTest 2, DatabaseEngineTest 1,
NoSecretsInLogsTest 1.

**Not yet run on real PostgreSQL.** There is no Docker or PostgreSQL on the dev machine, and
running a downloaded PostgreSQL binary was not permitted in this session. The `server` CI job is
the first real PostgreSQL run; `DatabaseEngineTest` fails the job if the suite silently fell back
to H2. Things that could differ on PostgreSQL and were checked by reading only: Hibernate
`ddl-auto=validate` column types (uuid, `timestamp(6) with time zone`, double precision, varchar
lengths), UUID ordering in the keyset query (internally consistent in either database), and the
aborted transaction after a unique violation in the settings first write (mapped to 412).
`docker build` / `docker compose up` were also not run (no Docker).

## Design choices worth reviewing

1. **Client UUIDs are scoped per device** (unique key `(device_id, session_id)` and
   `(device_id, event_id)`). The brief said "same id from another device → 404/409 without
   leaking existence". With a global id, any answer to `PUT` that differs from a fresh id's 201
   reveals that the id exists. With scoped ids, device B uploading A's UUID gets its own
   independent row and exactly the response a fresh UUID gets; A's data is untouched
   (`IsolationTest`). Reads of another device's id are 404, identical to "never existed".
2. **Upserts are last-write-wins**: same body → 200 with nothing changed (including `updatedAt`),
   different body → 200 replaced, new → 201. Timestamps are truncated to microseconds before
   comparing so re-uploads with nanoseconds still count as unchanged.
3. **Event batches add or replace by id and never delete**; the batch is all-or-nothing; an event
   id already used under another session of the same device is 409. A changed event bumps its
   session's `updatedAt`, so `GET /sessions?since=` is a complete change feed.
4. **Summary = `DailySummaryBuilder`**: local days in `tz` (DST-aware), zero days included,
   a session counted wholly on its start day, per-session seconds/60 summed without rounding, and
   open sessions included (the History `@Query` does not filter `endedAt`). `tz` is required.
5. **Settings**: `{settings:{…}}` replaces the whole document. `If-Match: "N"` is required (428 if
   missing), `"0"` creates, and a mismatch, weak tag or garbage is 412. Compare-and-increment is
   one conditional `UPDATE`. An identical write keeps the version. `axes`, the baseline and the
   preset are excluded on purpose.
6. **400 vs 422**: 400 means the request could not be read (JSON, types, unknown fields, query
   parameters); 422 means it was read and the values are not acceptable. Problem `type` URIs point
   to anchors in the contract on GitHub.
7. **Strict JSON**: unknown fields, scalar coercions, duplicate keys, trailing tokens and
   NaN/Infinity are all rejected. This is also what enforces "never accepts raw motion".

## Security measures

- Token: 32 `SecureRandom` bytes, base64url (43 chars), returned once with `no-store`. Only the
  SHA-256 hex is stored. Lookup is by hash plus a constant-time `MessageDigest.isEqual` check.
  Malformed headers are rejected before any database access.
- Stateless Spring Security: CSRF, sessions, form/basic login and the default user are all off.
  Only `POST /devices` and `GET /health` are public. 401/403 are problem+json with an RFC 6750
  `WWW-Authenticate` header.
- Ownership: every repository method takes the device id and there is no unscoped read
  (`IsolationTest`).
- Validation: Bean Validation bounds, cross-field rules, a timestamp window from 2020-01-01 to
  now + 24 h, enums, batch ≤ 500, ≤ 5 000 events per session, settings ≤ 16 KiB, and bodies
  ≤ 512 KiB (checked by Content-Length and while streaming). DB CHECK constraints back these up.
- Logging: no bodies, headers or SQL binds are logged. Error details never echo values, and
  unexpected exceptions are logged by class and location only (`NoSecretsInLogsTest` checks that
  tokens and payload markers never reach the output).
- Actuator: only `health` is exposed, at `/api/v1/health`, with no details. The container runs as
  uid 10001, and compose adds read-only, no-new-privileges and localhost ports.

## Proposals / open questions for the Lead

1. **Accept scoped client ids** (choice 1) instead of the literal 404/409, or decide otherwise.
2. **Data contract gaps**: add a "Sync (v1)" section to `data-contracts.md` pointing at
   `api-contracts.md`. Confirm the bounds I chose: session ≤ 7 days, event ≤ 24 h, peak ≤ 180°,
   reminders ≤ 100 000, the settings ranges, and `within + sustained ≤ monitored + 0.01 s`. The app
   needs a local "synced/dirty" flag per session and event, which `data-contracts.md` does not have
   yet (Frontend task).
3. **Settings scope**: confirm that the baseline, learned axes, `axes` and the preset stay
   device-local, and whether the settings document needs a `schemaVersion`.
4. **Erase semantics**: should the app's "Delete all history" also call `DELETE /devices/me`?
   Should there be a `DELETE /api/v1/sessions` that clears history but keeps the device and its
   settings, mirroring D-012's separate actions? Is an event delete needed?
5. **Rate limiting** (not implemented): needed before any public deployment, especially for the
   unauthenticated `POST /devices` (DB-fill abuse, R-14). Options are a per-IP limit at the
   proxy, bucket4j in the app, or App Attest / DeviceCheck on registration. 429 is reserved.
6. **Token lifecycle**: add a rotation endpoint, store the token in the Keychain with
   `ThisDeviceOnly` (or iCloud Keychain sync for restore on a new phone), and decide what happens
   on reinstall. The current behaviour is that the data is orphaned unless the Keychain item
   survives.
7. **Deployment**: none yet. Needs a host (e.g. Fly.io, Render or a small VPS with managed
   PostgreSQL), TLS and HSTS at the edge, secrets via env, backup retention (R-15), monitoring, a
   privacy policy and an updated App Store label (privacy review §9). Multi-device sync for one
   user would need accounts (Sign in with Apple) and a conflict rule beyond last-write-wins.
8. **Sync recipe**: `since` = last seen `updatedAt` minus 1 minute, to tolerate commit-order skew
   between concurrent transactions. A monotonically increasing change sequence would be stricter
   if it ever matters.
9. **Retention**: no automatic expiry (same open question as R-08).
10. Task board entries for the Lead: "Backend: run the server job on real PostgreSQL (first CI
    run)", "Frontend: opt-in sync toggle + Keychain token + upload queue", "QA: review the server
    privacy/security section".

## Known limitations

- First real-PostgreSQL run happens in CI; Docker image and compose are untested.
- No rate limiting, token rotation, metrics or deployment.
- Hibernate `validate` is on, so schema changes require a new Flyway migration (by design).
