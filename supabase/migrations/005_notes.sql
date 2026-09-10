-- 005_notes.sql — NOTES module: notes, tags, note↔tag links + RLS.
-- (Numbered 005: 004_invite_activation.sql already exists.)
--
-- Follows the repo's sync conventions (001_schema.sql header): client-generated UUID
-- PKs (offline creation), updated_at for LWW conflict resolution (server clock
-- authoritative via set_updated_at trigger), deleted_at tombstones — sync engines
-- never hard-delete synced rows.
--
-- Permission mapping (module.action — NEW 'notes' module, see
-- permissions/permissions-schema.json):
--   notes            -> notes.view / create / edit / delete
--   note_tags        -> notes.view for SELECT; create-or-edit for INSERT;
--                       edit for UPDATE (rename / tombstone); delete for hard DELETE
--   note_tag_links   -> notes.view for SELECT; create-or-edit for INSERT;
--                       edit for UPDATE (soft unlink/relink via deleted_at);
--                       delete for hard DELETE
--
-- Lifecycle & permission decisions (documented per spec):
--   * The app soft-deletes via UPDATE (sets deleted_at), like every other synced
--     table. Trash / restore / complete / pin are ALL status-column UPDATEs and are
--     guarded by notes.edit — consistent with bookings, where tombstoning via UPDATE
--     is guarded by booking.edit at the RLS layer.
--   * notes.delete guards the hard DELETE policies (defense in depth, same as every
--     other table) and is the CLIENT-SIDE gate for "delete forever" (purging a note
--     from Trash, i.e. the tombstoning UPDATE fired from the Trash screen, and the
--     30-day auto-purge sweep). RLS cannot distinguish which column an UPDATE
--     touches, so the purge distinction is enforced in the apps + hard-DELETE policy,
--     exactly like booking.delete today.
--   * Owners pass every check implicitly (has_perm short-circuits on is_owner).
--
-- INSERT on note_tags / note_tag_links accepts notes.create OR notes.edit:
-- a Staff-preset member (view + create) must be able to tag the note they are
-- creating; an editor tagging an existing note is performing an edit.

-- ============ ENUM ============
create type note_status as enum ('active', 'completed', 'trashed');

-- ============ notes ============
create table notes (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  kind text not null default 'note' check (kind in ('note', 'checklist')),
  title text,                          -- optional; a note may be body-only
  content text,                        -- plain-text body (kind='note')
  checklist jsonb not null default '[]',  -- kind='checklist': array of {id, text, done}
  color text,                          -- booking-colors.json key; NULL = default themed
  pinned boolean not null default false,
  status note_status not null default 'active',
  completed_at timestamptz,            -- set when status -> 'completed'
  trashed_at timestamptz,              -- set when status -> 'trashed' (30-day purge anchor)
  created_by uuid not null references auth.users(id),
  updated_by uuid references auth.users(id),           -- audit
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

comment on table notes is
  'Business notes & checklists. status drives the drawer sections (active/completed/trashed); trashed_at anchors the client-side 30-day purge; deleted_at is the sync tombstone (purge = tombstone).';
comment on column notes.checklist is
  'kind=checklist only: JSON array of {id, text, done}. Kept as one jsonb blob (not child rows): items are edited as a unit and LWW-merged per note.';
comment on column notes.color is
  'Color key from booking-colors.json (e.g. tomato, peacock). NULL = default themed surface.';

create index idx_notes_biz_status on notes (business_id, status)
  where deleted_at is null;

-- ============ note_tags ============
create table note_tags (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

comment on table note_tags is
  'Per-business note tags (Keep-style labels). Case-insensitive unique per business over LIVE rows only — a tombstoned tag''s name can be reused.';

-- Live tags: case-insensitive uniqueness per business; tombstones do not block reuse.
create unique index uq_note_tags_biz_name
  on note_tags (business_id, lower(name))
  where deleted_at is null;

-- ============ note_tag_links ============
-- Soft links (deleted_at) so untag/retag round-trips through sync as row updates,
-- never hard deletes. updated_at (not in the original column spec) is REQUIRED by the
-- repo's sync convention: flipping deleted_at on untag/retag must bump the LWW cursor
-- or incremental pulls (updated_at > cursor) would miss the change.
create table note_tag_links (
  note_id uuid not null references notes(id) on delete cascade,
  tag_id uuid not null references note_tags(id) on delete cascade,
  business_id uuid not null references businesses(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (note_id, tag_id)
);

comment on table note_tag_links is
  'Note↔tag assignments. Soft links: untag sets deleted_at, retag clears it (the PK row is reused). business_id denormalized for direct RLS checks.';

create index idx_note_tag_links_tag on note_tag_links (tag_id);

-- ============ updated_at TRIGGERS (LWW) ============
create trigger trg_notes_updated_at
  before insert or update on notes
  for each row execute function set_updated_at();
create trigger trg_note_tags_updated_at
  before insert or update on note_tags
  for each row execute function set_updated_at();
create trigger trg_note_tag_links_updated_at
  before insert or update on note_tag_links
  for each row execute function set_updated_at();

-- ============ RLS ============
alter table notes enable row level security;
alter table note_tags enable row level security;
alter table note_tag_links enable row level security;

-- notes
create policy notes_select on notes
  for select using (has_perm(business_id, 'notes', 'view'));
create policy notes_insert on notes
  for insert with check (has_perm(business_id, 'notes', 'create'));
create policy notes_update on notes
  for update using (has_perm(business_id, 'notes', 'edit'))
  with check (has_perm(business_id, 'notes', 'edit'));
create policy notes_delete on notes
  for delete using (has_perm(business_id, 'notes', 'delete'));

-- note_tags
create policy note_tags_select on note_tags
  for select using (has_perm(business_id, 'notes', 'view'));
create policy note_tags_insert on note_tags
  for insert with check (
    has_perm(business_id, 'notes', 'create')
    or has_perm(business_id, 'notes', 'edit')
  );
create policy note_tags_update on note_tags
  for update using (has_perm(business_id, 'notes', 'edit'))
  with check (has_perm(business_id, 'notes', 'edit'));
create policy note_tags_delete on note_tags
  for delete using (has_perm(business_id, 'notes', 'delete'));

-- note_tag_links
create policy note_tag_links_select on note_tag_links
  for select using (has_perm(business_id, 'notes', 'view'));
create policy note_tag_links_insert on note_tag_links
  for insert with check (
    has_perm(business_id, 'notes', 'create')
    or has_perm(business_id, 'notes', 'edit')
  );
create policy note_tag_links_update on note_tag_links
  for update using (has_perm(business_id, 'notes', 'edit'))
  with check (has_perm(business_id, 'notes', 'edit'));
create policy note_tag_links_delete on note_tag_links
  for delete using (has_perm(business_id, 'notes', 'delete'));
