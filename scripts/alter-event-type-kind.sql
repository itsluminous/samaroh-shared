-- alter-event-type-kind.sql — add event_types.kind to an EXISTING database
-- WITHOUT dropping/recreating (the consolidated baseline 001_schema.sql already
-- includes this column for fresh databases; run this instead of a full reset).
--
-- kind: 'booking' = real customer booking; 'marker' = auspicious-day
-- self-indicator (e.g. Lagan, Tilak) — highlights the day on the calendar,
-- has no customer/payments, and is excluded from booking counts and revenue.
--
-- Idempotence note: 'add column if not exists' makes a re-run harmless; the
-- backfill is naturally idempotent. The backfill UPDATE fires the
-- set_updated_at trigger, bumping updated_at so clients pick the change up
-- on their next incremental sync.

alter table event_types
  add column if not exists kind text not null default 'booking'
    check (kind in ('booking', 'marker'));

comment on column event_types.kind is
  'booking = real customer booking; marker = auspicious-day self-indicator (Lagan/Tilak style): calendar highlight only, no customer or payments, excluded from reports.';

-- Backfill: the two built-in auspicious-day presets become markers.
-- Matches on label because presets are per-business plain-text rows.
update event_types set kind = 'marker' where lower(label) in ('lagan', 'tilak');
