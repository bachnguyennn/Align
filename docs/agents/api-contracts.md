# API contracts (Phase 2 — not started)

The MVP has no backend. These are draft endpoints for the optional sync service, to be agreed by
the Backend and Data agents before implementation:

- `POST /api/v1/sessions`
- `PATCH /api/v1/sessions/{session_id}`
- `POST /api/v1/sessions/{session_id}/events`
- `GET /api/v1/sessions`
- `GET /api/v1/analytics/summary`
- `GET /api/v1/settings` / `PUT /api/v1/settings`

Payloads will mirror `data-contracts.md`. Raw motion telemetry is never uploaded. Sync needs
explicit user consent.
