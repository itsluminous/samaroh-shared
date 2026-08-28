-- 006_event_types.sql — event-type presets move from static config to the database.
--
-- Until now the booking event types were the 7 hard-coded entries in
-- event-types.json (localized display names via the string catalog). Users can
-- now manage their own presets, so each business gets its own rows here.
--
-- DESIGN DECISIONS
--   * label is PLAIN TEXT USER DATA, not a catalog key. Presets are no longer
--     localized per-locale: whatever the user typed (or the seed inserted) is
--     what every member sees, in every app language. See
--     docs/event-type-presets.md for the rationale and the seeding-in-English
--     tradeoff.
--   * bookings.event_type / bookings.event_icon stay as recorded free text —
--     bookings are NOT re-pointed at this table. Deleting a preset therefore
--     never touches existing bookings; they keep their recorded type and icon.
--   * Soft delete via deleted_at like every other synced table, so uniqueness
--     is a PARTIAL unique index over live rows only (a deleted preset's name
--     can be reused).
--   * SEEDING: this migration seeds the 7 built-ins for every EXISTING
--     non-deleted business (English labels — the file's canonical locale).
--     For FUTURE businesses seeding is CLIENT-SIDE: the app that creates the
--     business inserts the presets from event-types.json (the seed template)
--     in the same flow, in the app's current language if it chooses.

-- ============ TABLE ============
create table event_types (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  label text not null,               -- plain-text display name (user data, not a catalog key)
  icon text not null,                -- emoji shown on the calendar / booking form
  color text,                        -- default calendar color key from booking-colors.json; null = themed default
  sort_order int not null default 0, -- display order in pickers and the manage screen
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

comment on table event_types is
  'Per-business booking event-type presets, user-managed. Seeded from event-types.json (the seed template): by migration 006 for pre-existing businesses, client-side at business creation for new ones.';
comment on column event_types.label is
  'Plain-text display name. User data — NOT localized; not a string-catalog key.';
comment on column event_types.color is
  'Default calendar color key from booking-colors.json (e.g. tomato). NULL = standard themed color.';

-- Live presets must have unique names per business; tombstoned rows do not block reuse.
create unique index uq_event_types_biz_label
  on event_types (business_id, label)
  where deleted_at is null;

-- ============ updated_at TRIGGER (LWW, same as every synced table) ============
create trigger trg_event_types_updated_at
  before insert or update on event_types
  for each row execute function set_updated_at();

-- ============ RLS ============
-- SELECT: any active member — consistent with businesses_select. Every member
-- needs the presets to render the calendar and booking form regardless of
-- their booking.* permissions.
-- Writes: settings.manage_business (has_perm already grants owners implicitly).
alter table event_types enable row level security;

create policy event_types_select on event_types
  for select using (is_active_member(business_id));
create policy event_types_insert on event_types
  for insert with check (has_perm(business_id, 'settings', 'manage_business'));
create policy event_types_update on event_types
  for update using (has_perm(business_id, 'settings', 'manage_business'))
  with check (has_perm(business_id, 'settings', 'manage_business'));
create policy event_types_delete on event_types
  for delete using (has_perm(business_id, 'settings', 'manage_business'));

-- ============ SEED: built-ins for every existing business ============
-- Labels/emoji/colors mirror event-types.json (labels in English — the
-- canonical locale; see the header note). sort_order preserves the file order.
insert into event_types (business_id, label, icon, color, sort_order)
select b.id, s.label, s.icon, s.color, s.sort_order
from businesses b
cross join (
  values
    ('Engagement',   '💍', 'flamingo',  0),
    ('Tilak',        '🪔', 'tangerine', 1),
    ('Wedding',      '💒', 'tomato',    2),
    ('Room Booking', '🏨', 'blueberry', 3),
    ('Birthday',     '🎂', 'banana',    4),
    ('Anniversary',  '👫🏻', 'sage',      5),
    ('Custom',       '✨', 'grape',     6)
) as s(label, icon, color, sort_order)
where b.deleted_at is null;
