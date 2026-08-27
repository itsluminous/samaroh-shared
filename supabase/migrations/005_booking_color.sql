-- 005_booking_color.sql — bookings get a user-chosen calendar color.
--
-- Requirement: the booking form offers a curated 16-swatch color picker
-- (keys defined in booking-colors.json at the repo root). The chosen key is
-- stored here; NULL means "Default" — the apps render the booking in the
-- standard themed (purple) look, exactly as before this migration.
--
-- RLS: unaffected. The bookings policies in 002_rls.sql gate on
-- has_perm(business_id, …) and do not enumerate columns, and no column-level
-- grants exist — the new column is covered automatically.

alter table bookings
  add column color text;

comment on column bookings.color is
  'Calendar color key from booking-colors.json (e.g. tomato, peacock). NULL = default themed color.';
