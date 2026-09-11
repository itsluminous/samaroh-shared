-- 007_notes_fine_perms.sql — fine-grained notes permissions: view_checklists + toggle_checklist.
--
-- Owner requirement: members get finer notes control —
--   (a) viewing NOTES (kind='note') and CHECKLISTS (kind='checklist') are gated
--       separately: notes.view vs notes.view_checklists;
--   (b) a member may be allowed to check/uncheck checklist items without full
--       notes.edit: notes.toggle_checklist.
--
-- BACK-COMPAT / INHERITANCE (mirrors permissions/permissions-schema.json — clients
-- must normalize IDENTICALLY):
--   * view_checklists ABSENT  -> inherits notes.view  (existing members keep seeing
--                                checklists exactly as before this migration)
--   * toggle_checklist ABSENT -> inherits notes.edit  (existing editors keep ticking
--                                items exactly as before this migration)
-- The inheritance lives INSIDE has_notes_perm() below (coalesce over the explicit key,
-- then the fallback key, then false) so RLS and clients agree byte-for-byte.
--
-- Design (repo guard-trigger pattern — 004 invite-activation, 006 invoice-counter:
-- RLS decides WHICH rows, a BEFORE UPDATE guard trigger pins WHAT may change):
--   * notes SELECT is REPLACED and splits by kind:
--       kind='note'      -> has_perm(biz,'notes','view')            (unchanged gate)
--       kind='checklist' -> has_notes_perm(biz,'view_checklists')   (inherits view)
--   * notes UPDATE is REPLACED: full notes.edit as today, OR — for kind='checklist'
--     only — has_notes_perm(biz,'toggle_checklist') (inherits edit).
--   * guard trigger guard_notes_checklist_toggle(): an updater who lacks notes.edit
--     (and is not owner / not a server-side path) and therefore passed RLS only via
--     toggle_checklist may ONLY flip 'done' flags inside the checklist jsonb:
--     the array length, element order, and every per-element field EXCEPT 'done'
--     (ids, texts, any future fields) are compared field-by-field OLD vs NEW and any
--     drift raises. Every other column is compared OLD vs NEW too, with exactly two
--     exemptions: updated_at (server-set by trg_notes_updated_at) and updated_by
--     (audit — but it must be the caller when it changes).
--
-- SCOPE NOTES:
--   * note_tags / note_tag_links SELECT stays on notes.view — tags are a notes-level
--     concept; a checklist-only member (view=false, view_checklists=true) sees
--     checklists without tag chips. Deliberate: keeps 007 additive and minimal.
--   * INSERT/DELETE on notes are untouched (create / delete gates unchanged).
--   * Owners pass every check implicitly (is_owner short-circuits, as everywhere).
--   * Trigger order on notes UPDATE is alphabetical: trg_guard_notes_checklist_toggle
--     fires BEFORE trg_notes_updated_at, so the guard sees the client-sent
--     updated_at — which is why updated_at is exempt rather than validated.

-- ============ HELPER: notes-module permission with inheritance ============
-- Same shape as has_perm (002) — security definer, search_path pinned — but the
-- action key falls back to its inheritance parent when ABSENT (json null):
--   view_checklists -> view, toggle_checklist -> edit, anything else -> itself.
-- NOTE: an EXPLICIT false never falls through — coalesce only skips SQL NULL
-- (absent key), which is exactly the schema's "absent inherits" contract.
create or replace function has_notes_perm(biz uuid, action text)
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
            m.permissions -> 'notes' ->> action,
            m.permissions -> 'notes' ->> case action
              when 'view_checklists'  then 'view'
              when 'toggle_checklist' then 'edit'
              else action
            end,
            'false'
          )::boolean
  );
$$;

-- ============ POLICY: notes SELECT splits by kind ============
-- Replaced (not layered) so the row-visibility rule reads as one expression (006 style).
drop policy if exists notes_select on notes;
create policy notes_select on notes
  for select using (
    case kind
      when 'checklist' then has_notes_perm(business_id, 'view_checklists')
      else has_perm(business_id, 'notes', 'view')
    end
  );

-- ============ POLICY: notes UPDATE gains the checklist-toggle path ============
drop policy if exists notes_update on notes;
create policy notes_update on notes
  for update using (
    has_perm(business_id, 'notes', 'edit')
    or (kind = 'checklist' and has_notes_perm(business_id, 'toggle_checklist'))
  )
  with check (
    has_perm(business_id, 'notes', 'edit')
    or (kind = 'checklist' and has_notes_perm(business_id, 'toggle_checklist'))
  );

-- ============ GUARD: toggle-only updaters may ONLY flip 'done' flags ============
create or replace function guard_notes_checklist_toggle()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Server-side paths (service role, triggers — no JWT uid) and fully-privileged
  -- members stay unrestricted. is_owner is implied by has_perm but checked first
  -- to short-circuit the common owner path (006 pattern).
  if auth.uid() is null
     or is_owner(old.business_id)
     or has_perm(old.business_id, 'notes', 'edit') then
    return new;
  end if;

  -- From here the updater passed RLS only via notes.toggle_checklist:
  -- the ONLY permitted change is the 'done' flag of existing checklist items
  -- (plus updated_at — server-set — and updated_by, which must be the caller).
  if old.kind <> 'checklist' then
    -- Unreachable via RLS (the toggle path is kind-gated) — defense in depth.
    raise exception 'notes: toggle_checklist applies to checklists only';
  end if;

  if new.id <> old.id
     or new.business_id <> old.business_id
     or new.kind <> old.kind
     or new.title is distinct from old.title
     or new.content is distinct from old.content
     or new.color is distinct from old.color
     or new.pinned <> old.pinned
     or new.status <> old.status
     or new.completed_at is distinct from old.completed_at
     or new.trashed_at is distinct from old.trashed_at
     or new.created_by <> old.created_by
     or new.created_at <> old.created_at
     or new.deleted_at is distinct from old.deleted_at
  then
    raise exception 'notes: toggle_checklist may only change checklist item done flags';
  end if;

  if new.updated_by is distinct from old.updated_by
     and new.updated_by is distinct from auth.uid() then
    raise exception 'notes: toggle_checklist must stamp updated_by with the caller';
  end if;

  -- Checklist jsonb, compared field-by-field: both must be arrays of the SAME length,
  -- and each element — in the SAME position — must be identical once 'done' is
  -- removed (ids, texts, ordering, and any future per-item fields all pinned).
  if jsonb_typeof(old.checklist) <> 'array' or jsonb_typeof(new.checklist) <> 'array' then
    raise exception 'notes: checklist must be a json array';
  end if;

  if jsonb_array_length(new.checklist) <> jsonb_array_length(old.checklist) then
    raise exception 'notes: toggle_checklist may not add or remove checklist items';
  end if;

  if exists (
    select 1
    from generate_series(0, jsonb_array_length(old.checklist) - 1) as i
    where (old.checklist -> i) - 'done' <> (new.checklist -> i) - 'done'
       or coalesce(jsonb_typeof(new.checklist -> i -> 'done'), 'null')
            not in ('boolean', 'null')
  ) then
    raise exception 'notes: toggle_checklist may only change checklist item done flags';
  end if;

  return new;
end;
$$;

create trigger trg_guard_notes_checklist_toggle
  before update on notes
  for each row execute function guard_notes_checklist_toggle();
