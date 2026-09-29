-- 009_files_tab.sql — FILES module: folders, files, folder_access + RLS.
-- Design: docs/files-tab-design.md (the cross-platform contract both apps implement).
--
-- WHAT THESE TABLES ARE. A per-business METADATA INDEX over files whose BYTES live in
-- Google Drive — exactly the expense_attachments / master_items.drive_* posture
-- (001 header, 003 header): the file itself never touches Supabase Storage; every
-- uploader's own Drive holds the bytes under `Samaroh/{Business}/files/{folder path}`,
-- shared anyone-with-link at upload time so every member can open it. The index gives
-- offline listing, search, permissions and sync; Drive is dumb blob storage.
--
-- Sync conventions (001 header): client-generated UUID PKs (offline creation), updated_at
-- for LWW (server clock authoritative via set_updated_at), deleted_at tombstones — sync
-- engines never hard-delete synced rows. ALL THREE tables here are MUTABLE rows with
-- updated_at, so a tombstone (UPDATE deleted_at) bumps the LWW cursor and ONE pull leg
-- suffices — deliberately NOT the immutable/created_at shape of expense_attachments,
-- whose tombstones needed a second pull leg (Android ADR-084).
--
-- Permission mapping (module.action — NEW 'files' module, permissions/permissions-schema.json):
--   files.view            -> SELECT on folders / files
--   files.upload          -> INSERT on files; UPDATE of own files (upsert-retry safety)
--   files.delete          -> tombstone (UPDATE deleted_at) + hard DELETE on files / folders
--   files.manage_folders  -> INSERT / rename (UPDATE) on folders.
--                            ABSENT = inherits files.upload (has_files_perm below, the
--                            007 has_notes_perm shape): someone allowed to upload may make
--                            a folder to file it in; owners set it false explicitly to lock
--                            the hierarchy. An explicit false never falls through.
--   Owners pass every check implicitly (is_owner short-circuits, as everywhere).
--
-- Folder-level access = RESTRICTED FOLDERS (allow-list model, the simplest RLS can
-- enforce): folders.restricted=true means only the owner and members listed in
-- folder_access (per business_members row) may see that folder and EVERYTHING under it.
-- Subfolders inherit: can_access_folder() walks up the parent chain and requires the
-- caller to pass EVERY restricted ancestor's allow-list. Root (folder_id NULL) is never
-- restricted. Only the OWNER may flip `restricted` or edit folder_access (a permission
-- concern, owner-managed like business_members).
--
-- Guard triggers (repo pattern 004/006/007 — RLS decides WHICH rows, a BEFORE UPDATE
-- guard pins WHAT may change):
--   * folders: non-owners may not change restricted / parent_id / business_id /
--     created_by / created_at / id; updaters without files.delete may not change
--     deleted_at; updaters without files.manage_folders may not change name.
--   * files: updaters without files.delete may change NOTHING but name and updated_at
--     (the UPDATE path exists for them only so an UPSERT retry of a row they already
--     pushed does not 403 — PostgREST upsert hits the UPDATE policy on conflict).
--
-- Uniqueness: folder names are unique per parent per business, CASE-INSENSITIVELY, over
-- LIVE rows only (partial index over lower(name), the 008 lesson). File names are NOT
-- unique (Drive allows duplicates; camera exports repeat names) — clients show them as-is.
--
-- No permission backfill: existing members' permissions jsonb has no 'files' key, so
-- absent = false and the module stays hidden until the owner grants it (same launch
-- posture as notes in 005). Presets (client-side, both apps): Viewer = view;
-- Staff = view + upload (manage_folders inherited); Manager = all four.

-- ============ folders ============
create table folders (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  parent_id uuid references folders(id) on delete cascade,   -- NULL = top level ("All files")
  name text not null
    check (length(btrim(name)) between 1 and 120 and position('/' in name) = 0),
  restricted boolean not null default false,                 -- owner-only flag, see header
  created_by uuid not null references auth.users(id),
  updated_by uuid references auth.users(id),                 -- audit
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

comment on table folders is
  'Files-module folder tree (metadata index). parent_id NULL = top level. restricted=true limits the folder AND everything under it to the owner + folder_access members. Name unique per parent CASE-INSENSITIVELY over LIVE rows only.';
comment on column folders.restricted is
  'Owner-only flag (guard trigger). true = only owner + folder_access members see this folder and its whole subtree.';

-- Live folders: case-insensitive unique name per parent per business; tombstones do not
-- block reuse. NULL parent_id is folded to the nil uuid so top-level names are unique too.
create unique index uq_folders_biz_parent_name
  on folders (business_id, coalesce(parent_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(name))
  where deleted_at is null;

create index idx_folders_biz_parent on folders (business_id, parent_id)
  where deleted_at is null;

-- ============ files ============
create table files (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  folder_id uuid references folders(id) on delete cascade,   -- NULL = top level
  name text not null
    check (length(btrim(name)) between 1 and 255 and position('/' in name) = 0),
  mime_type text not null,
  size_bytes bigint not null check (size_bytes between 0 and 26214400),  -- 25 MiB cap (design §limits)
  -- Google Drive = THE store. NOT NULL: clients push the row only AFTER the Drive
  -- upload succeeded (Android upload-before-row-push, ADR-018; web uploads inline),
  -- so a server row is always openable. Thumbnails / view / download URLs are DERIVED
  -- from this id (drive.google.com/thumbnail, /file/d/{id}/view, uc?export=download)
  -- — no link columns to drift.
  drive_file_id text not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

comment on table files is
  'Files-module file index. Bytes live in the UPLOADER''s Google Drive (drive_file_id, anyone-with-link); this row is metadata only. folder_id NULL = top level. Names may repeat. Mutable row: tombstone bumps updated_at (single pull leg).';
comment on column files.drive_file_id is
  'Drive file id in the uploader''s Drive, shared anyone-with-link. NOT NULL — the row is pushed only after the upload succeeded.';

create index idx_files_biz_folder on files (business_id, folder_id)
  where deleted_at is null;

-- ============ folder_access ============
-- Allow-list rows for RESTRICTED folders. Keyed by business_members.id (stable across
-- invite → active; an owner can grant access at invite time). Soft links (deleted_at)
-- with updated_at, the note_tag_links shape: revoke sets deleted_at, re-grant clears it
-- on the SAME PK row.
create table folder_access (
  folder_id uuid not null references folders(id) on delete cascade,
  member_id uuid not null references business_members(id) on delete cascade,
  business_id uuid not null references businesses(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (folder_id, member_id)
);

comment on table folder_access is
  'Allow-list for restricted folders: (folder, member) rows. Owner-managed. Soft link: revoke = set deleted_at, re-grant = clear it on the same row. business_id denormalized for RLS.';

create index idx_folder_access_member on folder_access (member_id)
  where deleted_at is null;

-- ============ updated_at TRIGGERS (LWW) ============
create trigger trg_folders_updated_at
  before insert or update on folders
  for each row execute function set_updated_at();
create trigger trg_files_updated_at
  before insert or update on files
  for each row execute function set_updated_at();
create trigger trg_folder_access_updated_at
  before insert or update on folder_access
  for each row execute function set_updated_at();

-- ============ HELPER: files-module permission with inheritance ============
-- Same shape as has_notes_perm (007): security definer, search_path pinned; the action
-- falls back to its inheritance parent when ABSENT (json null) — manage_folders -> upload.
-- coalesce skips SQL NULL only, so an EXPLICIT false never falls through.
create or replace function has_files_perm(biz uuid, action text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select is_owner(biz) or exists (
    select 1
    from business_members m
    where m.business_id = biz
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.deleted_at is null
      and coalesce(
            m.permissions -> 'files' ->> action,
            m.permissions -> 'files' ->> case action
              when 'manage_folders' then 'upload'
              else action
            end,
            'false'
          )::boolean
  );
$$;

-- ============ HELPER: folder-level access (restricted-folder allow-lists) ============
-- TRUE when the caller may see folder `fid` (and therefore its contents): fid NULL (top
-- level) always; owner always; otherwise the caller must be on the allow-list of EVERY
-- restricted folder in the chain fid -> ... -> root (subfolders inherit restrictions;
-- nested restrictions intersect). Depth capped at 64 to bound a corrupt cycle.
-- security definer: reads folders/folder_access/business_members without recursing
-- through their own RLS (the 002 helper pattern).
create or replace function can_access_folder(biz uuid, fid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select fid is null
    or is_owner(biz)
    or not exists (
      with recursive chain as (
        select f.id, f.parent_id, f.restricted, 1 as depth
        from folders f
        where f.id = fid
        union all
        select p.id, p.parent_id, p.restricted, c.depth + 1
        from folders p
        join chain c on p.id = c.parent_id
        where c.depth < 64
      )
      select 1
      from chain c
      where c.restricted
        and not exists (
          select 1
          from folder_access fa
          join business_members m on m.id = fa.member_id
          where fa.folder_id = c.id
            and fa.deleted_at is null
            and m.user_id = auth.uid()
            and m.status = 'active'
            and m.deleted_at is null
        )
    );
$$;

-- The caller's own membership row? (folder_access SELECT: members see the rows that
-- name THEM — enough to render the "Restricted" badge — owners see every row.)
create or replace function is_my_member_row(mid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from business_members m
    where m.id = mid
      and m.user_id = auth.uid()
      and m.deleted_at is null
  );
$$;

-- ============ GUARD: folders UPDATE ============
create or replace function guard_folders_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Server-side paths (service role, no JWT uid) stay unrestricted.
  if auth.uid() is null then
    return new;
  end if;

  -- Structural / ownership columns never move via UPDATE (folder MOVE is out of scope;
  -- clients re-create instead).
  if new.id <> old.id
     or new.business_id <> old.business_id
     or new.parent_id is distinct from old.parent_id
     or new.created_by <> old.created_by
     or new.created_at <> old.created_at then
    raise exception 'folders: id, business_id, parent_id, created_by and created_at are immutable';
  end if;

  if is_owner(old.business_id) then
    return new;
  end if;

  -- From here: a non-owner member who passed RLS via manage_folders and/or delete.
  if new.restricted <> old.restricted then
    raise exception 'folders: only the owner may change restricted';
  end if;
  if new.deleted_at is distinct from old.deleted_at
     and not has_files_perm(old.business_id, 'delete') then
    raise exception 'folders: files.delete is required to delete or restore a folder';
  end if;
  if new.name <> old.name
     and not has_files_perm(old.business_id, 'manage_folders') then
    raise exception 'folders: files.manage_folders is required to rename a folder';
  end if;
  if new.updated_by is distinct from old.updated_by
     and new.updated_by is distinct from auth.uid() then
    raise exception 'folders: updated_by must be the caller';
  end if;
  return new;
end;
$$;

create trigger trg_guard_folders_update
  before update on folders
  for each row execute function guard_folders_update();

-- ============ GUARD: files UPDATE ============
create or replace function guard_files_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return new;
  end if;

  -- Immutable for everyone via UPDATE: identity, placement and the Drive reference.
  -- (A replaced file is a NEW row; file MOVE is out of scope in v1.)
  if new.id <> old.id
     or new.business_id <> old.business_id
     or new.folder_id is distinct from old.folder_id
     or new.drive_file_id <> old.drive_file_id
     or new.mime_type <> old.mime_type
     or new.size_bytes <> old.size_bytes
     or new.created_by <> old.created_by
     or new.created_at <> old.created_at then
    raise exception 'files: only name and deleted_at may change on an existing file';
  end if;

  if is_owner(old.business_id) or has_files_perm(old.business_id, 'delete') then
    return new;
  end if;

  -- From here the updater passed RLS only as the file's uploader (files.upload):
  -- an upsert retry or a rename — never a tombstone.
  if new.deleted_at is distinct from old.deleted_at then
    raise exception 'files: files.delete is required to delete or restore a file';
  end if;
  return new;
end;
$$;

create trigger trg_guard_files_update
  before update on files
  for each row execute function guard_files_update();

-- ============ RLS ============
alter table folders enable row level security;
alter table files enable row level security;
alter table folder_access enable row level security;

-- folders
create policy folders_select on folders
  for select using (
    has_files_perm(business_id, 'view')
    and can_access_folder(business_id, id)
  );
create policy folders_insert on folders
  for insert with check (
    has_files_perm(business_id, 'manage_folders')
    and can_access_folder(business_id, parent_id)
    and created_by = auth.uid()
    and (not restricted or is_owner(business_id))
  );
create policy folders_update on folders
  for update using (
    (has_files_perm(business_id, 'manage_folders') or has_files_perm(business_id, 'delete'))
    and can_access_folder(business_id, id)
  )
  with check (
    (has_files_perm(business_id, 'manage_folders') or has_files_perm(business_id, 'delete'))
    and can_access_folder(business_id, id)
  );
create policy folders_delete on folders
  for delete using (
    has_files_perm(business_id, 'delete')
    and can_access_folder(business_id, id)
  );

-- files
create policy files_select on files
  for select using (
    has_files_perm(business_id, 'view')
    and can_access_folder(business_id, folder_id)
  );
create policy files_insert on files
  for insert with check (
    has_files_perm(business_id, 'upload')
    and can_access_folder(business_id, folder_id)
    and created_by = auth.uid()
  );
-- UPDATE: delete-holders (tombstone) OR the uploader of this very row (upsert retry /
-- rename; the guard trigger forbids them everything else, incl. deleted_at).
create policy files_update on files
  for update using (
    can_access_folder(business_id, folder_id)
    and (
      has_files_perm(business_id, 'delete')
      or (has_files_perm(business_id, 'upload') and created_by = auth.uid())
    )
  )
  with check (
    can_access_folder(business_id, folder_id)
    and (
      has_files_perm(business_id, 'delete')
      or (has_files_perm(business_id, 'upload') and created_by = auth.uid())
    )
  );
create policy files_delete on files
  for delete using (
    has_files_perm(business_id, 'delete')
    and can_access_folder(business_id, folder_id)
  );

-- folder_access (owner-managed; members read the rows naming themselves)
create policy folder_access_select on folder_access
  for select using (is_owner(business_id) or is_my_member_row(member_id));
create policy folder_access_insert on folder_access
  for insert with check (is_owner(business_id));
create policy folder_access_update on folder_access
  for update using (is_owner(business_id))
  with check (is_owner(business_id));
create policy folder_access_delete on folder_access
  for delete using (is_owner(business_id));

-- ============ GRANTS ============
-- Supabase's default privileges already grant the API roles access to new public
-- tables/functions; stated explicitly here (guarded so the file also replays on a
-- plain scratch Postgres without those roles).
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant select, insert, update, delete on folders, files, folder_access to authenticated;
    grant execute on function has_files_perm(uuid, text) to authenticated;
    grant execute on function can_access_folder(uuid, uuid) to authenticated;
    grant execute on function is_my_member_row(uuid) to authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant all on folders, files, folder_access to service_role;
  end if;
end
$$;
