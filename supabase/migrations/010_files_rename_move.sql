-- 010_files_rename_move.sql — FILES module: file rename + file/folder MOVE (design D14 revised).
-- Design: docs/files-tab-design.md §D14 (2026-09-30 revision, owner feedback on the 0.18 drop).
--
-- 009 pinned `folders.parent_id` and `files.folder_id` as IMMUTABLE in the BEFORE UPDATE
-- guard triggers ("move is out of scope in v1; clients re-create"). The owner wants
-- Rename (files AND folders) and Move (files AND folders) in both apps. This migration
-- REPLACES the two guard functions (create or replace; the triggers themselves are
-- unchanged) so that:
--
--   * folders: `parent_id` MAY change. Non-owners need files.manage_folders (the same
--     permission as rename / create — moving is restructuring the hierarchy) AND access to
--     the NEW parent (`can_access_folder`; RLS WITH CHECK cannot see the not-yet-written
--     row's new chain, so the guard checks the destination explicitly). Everyone —
--     owners included — is refused a CYCLE (destination = the folder itself or any of its
--     live descendants) and a chain deeper than the RLS walk cap: a corrupt cycle would
--     otherwise make can_access_folder() loop to its 64-step guard on every query.
--   * files: `folder_id` MAY change under the EXISTING files_update policy — delete-holders,
--     or the uploader of this very row with files.upload (that is who may also rename it).
--     RLS WITH CHECK already requires access to the destination folder (folder_id is a
--     scalar of the new row). id / business_id / drive_file_id / mime_type / size_bytes /
--     created_by / created_at stay immutable.
--
-- Unchanged: uq_folders_biz_parent_name (a move into a parent that already has a live
-- folder of the same name is a 23505 — clients validate siblings at move time, exactly as
-- for rename); has_files_perm / can_access_folder helpers; every RLS policy. Drive is a
-- best-effort human-readable mirror: clients PATCH the Drive file name / parents when the
-- actor is linked and owns the bytes, and swallow 403/404 (the 053/084 delete posture).
--
-- IDEMPOTENT: `create or replace function` only. Validated on scratch Postgres 15 with the
-- 001→010 replay + RLS probes (owner move, staff move with/without manage_folders, cycle,
-- restricted destination).

-- ============ GUARD: folders UPDATE (replaces 009) ============
create or replace function guard_folders_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  cycle_hit boolean;
begin
  -- Server-side paths (service role, no JWT uid) stay unrestricted.
  if auth.uid() is null then
    return new;
  end if;

  -- Identity / ownership columns never move via UPDATE (parent_id is now allowed — see below).
  if new.id <> old.id
     or new.business_id <> old.business_id
     or new.created_by <> old.created_by
     or new.created_at <> old.created_at then
    raise exception 'folders: id, business_id, created_by and created_at are immutable';
  end if;

  -- MOVE (parent_id change): cycle guard for everyone. The destination may not be the
  -- folder itself, and walking UP from the destination must never reach this folder.
  if new.parent_id is distinct from old.parent_id and new.parent_id is not null then
    if new.parent_id = new.id then
      raise exception 'folders: a folder cannot be moved into itself';
    end if;
    with recursive chain as (
      select f.id, f.parent_id, 1 as depth
      from folders f
      where f.id = new.parent_id
      union all
      select p.id, p.parent_id, c.depth + 1
      from folders p
      join chain c on p.id = c.parent_id
      where c.depth < 64
    )
    select exists (select 1 from chain c where c.id = new.id) into cycle_hit;
    if cycle_hit then
      raise exception 'folders: a folder cannot be moved into one of its own subfolders';
    end if;
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
  if new.parent_id is distinct from old.parent_id then
    if not has_files_perm(old.business_id, 'manage_folders') then
      raise exception 'folders: files.manage_folders is required to move a folder';
    end if;
    if not can_access_folder(old.business_id, new.parent_id) then
      raise exception 'folders: no access to the destination folder';
    end if;
  end if;
  if new.updated_by is distinct from old.updated_by
     and new.updated_by is distinct from auth.uid() then
    raise exception 'folders: updated_by must be the caller';
  end if;
  return new;
end;
$$;

-- ============ GUARD: files UPDATE (replaces 009) ============
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

  -- Immutable for everyone via UPDATE: identity and the Drive reference. folder_id (MOVE)
  -- and name (RENAME) may change for whoever passed the files_update policy — the
  -- destination folder's access is enforced by that policy's WITH CHECK.
  if new.id <> old.id
     or new.business_id <> old.business_id
     or new.drive_file_id <> old.drive_file_id
     or new.mime_type <> old.mime_type
     or new.size_bytes <> old.size_bytes
     or new.created_by <> old.created_by
     or new.created_at <> old.created_at then
    raise exception 'files: only name, folder_id and deleted_at may change on an existing file';
  end if;

  if is_owner(old.business_id) or has_files_perm(old.business_id, 'delete') then
    return new;
  end if;

  -- From here the updater passed RLS only as the file's uploader (files.upload):
  -- an upsert retry, a rename or a move — never a tombstone.
  if new.deleted_at is distinct from old.deleted_at then
    raise exception 'files: files.delete is required to delete or restore a file';
  end if;
  return new;
end;
$$;

comment on function guard_folders_update() is
  'BEFORE UPDATE guard on folders (009, relaxed by 010): identity columns immutable; parent_id moves allowed with a cycle guard, files.manage_folders for non-owners and access to the destination; restricted owner-only; deleted_at needs files.delete; name needs files.manage_folders.';
comment on function guard_files_update() is
  'BEFORE UPDATE guard on files (009, relaxed by 010): identity + Drive reference immutable; name and folder_id may change for anyone who passed files_update; deleted_at needs files.delete.';
