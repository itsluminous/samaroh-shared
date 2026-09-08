-- ADR-048: per-business Google Calendar registry.
-- Adds business_settings.gcal_calendar_id — the app-created calendar (named after the
-- business) that this business's bookings push to. Replaces google_accounts.calendar_id
-- as the push target; that column stays only for the pre-app-created-scope primary
-- fallback and is otherwise deprecated.
--
-- Run this ONCE against an existing database (SQL editor or psql). New databases get
-- the column from the baseline schema (001_schema.sql) and do NOT need this script.
--
-- Until this is applied, Android holds business_settings pushes per-item (PGRST204,
-- self-healing — same pattern as ADR-027/030) and retries on the next sync; pulls are
-- unaffected.

alter table business_settings
  add column if not exists gcal_calendar_id text;
