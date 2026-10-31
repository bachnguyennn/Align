-- Align sync server, schema v1 (docs/agents/api-contracts.md).
-- Written for PostgreSQL 16; the test suite also runs it on H2 in PostgreSQL mode, so only
-- portable syntax is used here.

-- An anonymous device (D-018). The bearer token itself is never stored, only its SHA-256 hash.
create table device (
    id           uuid                        not null primary key,
    token_sha256 varchar(64)                 not null,
    created_at   timestamp(6) with time zone not null,
    constraint uq_device_token_sha256 unique (token_sha256)
);

-- MonitoringSession (data-contracts.md). Client UUIDs are scoped per device: the same UUID
-- uploaded by another device is a different row, so one device can never observe or touch
-- another device's session.
create table monitoring_session (
    pk                          bigint generated always as identity primary key,
    device_id                   uuid                        not null,
    session_id                  uuid                        not null,
    started_at                  timestamp(6) with time zone not null,
    ended_at                    timestamp(6) with time zone,
    monitored_duration_seconds  double precision            not null,
    within_threshold_seconds    double precision            not null,
    sustained_deviation_seconds double precision            not null,
    reminder_count              integer                     not null,
    calibration_version         integer                     not null,
    sensor_availability_status  varchar(16)                 not null,
    created_at                  timestamp(6) with time zone not null,
    updated_at                  timestamp(6) with time zone not null,
    constraint fk_session_device foreign key (device_id) references device (id) on delete cascade,
    constraint uq_session_device_session unique (device_id, session_id),
    constraint ck_session_durations check (monitored_duration_seconds >= 0
        and within_threshold_seconds >= 0 and sustained_deviation_seconds >= 0),
    constraint ck_session_counts check (reminder_count >= 0 and calibration_version >= 0),
    constraint ck_session_status check (sensor_availability_status in ('real', 'mock', 'unavailable')),
    constraint ck_session_interval check (ended_at is null or ended_at >= started_at)
);

-- GET /sessions pages by (updated_at, session_id); GET /analytics/summary filters by started_at.
create index ix_session_device_updated on monitoring_session (device_id, updated_at, session_id);
create index ix_session_device_started on monitoring_session (device_id, started_at);

-- PostureEvent (one sustained-tilt episode). Event UUIDs are also scoped per device.
create table posture_event (
    pk                     bigint generated always as identity primary key,
    session_pk             bigint                      not null,
    device_id              uuid                        not null,
    event_id               uuid                        not null,
    started_at             timestamp(6) with time zone not null,
    ended_at               timestamp(6) with time zone not null,
    deviation_type         varchar(16)                 not null,
    duration_seconds       double precision            not null,
    peak_deviation_degrees double precision            not null,
    reminder_triggered     boolean                     not null,
    created_at             timestamp(6) with time zone not null,
    updated_at             timestamp(6) with time zone not null,
    constraint fk_event_session foreign key (session_pk) references monitoring_session (pk) on delete cascade,
    constraint fk_event_device foreign key (device_id) references device (id) on delete cascade,
    constraint uq_event_device_event unique (device_id, event_id),
    constraint ck_event_type check (deviation_type in ('forward', 'backward', 'left', 'right')),
    constraint ck_event_values check (duration_seconds >= 0 and peak_deviation_degrees >= 0),
    constraint ck_event_interval check (ended_at >= started_at)
);

create index ix_event_session on posture_event (session_pk, started_at);

-- One settings document per device, with a version for optimistic concurrency (If-Match).
create table device_settings (
    device_id  uuid                        not null primary key,
    version    bigint                      not null,
    document   varchar(16384)              not null,
    updated_at timestamp(6) with time zone not null,
    constraint fk_settings_device foreign key (device_id) references device (id) on delete cascade,
    constraint ck_settings_version check (version >= 1)
);
