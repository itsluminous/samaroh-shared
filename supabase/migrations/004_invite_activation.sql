-- 004_invite_activation.sql — invite visibility + activation for EXISTING auth users.
--
-- The consolidated baseline covers only the new-signup half of the §3 invite flow
-- (trg_activate_pending_invites fires AFTER INSERT ON auth.users), and its RLS broke
-- the flow for users whose auth account already existed when the owner invited them:
--   1. business_members_select requires user_id = auth.uid() (or owner) — a pending
--      invite still has user_id NULL, so the invitee cannot even SEE the invitation
--      and the clients' join screens list nothing.
--   2. business_members_update is owner-only — the invitee cannot accept (activate)
--      their own invitation.
--   3. Nothing links user_id for auth accounts that PRE-DATE the invite: the
--      auth.users trigger never fires again for an existing account.
--
-- This migration is additive only:
--   * auth_email() / is_invited_member(biz) helpers
--   * invited-self SELECT policies on business_members and businesses (so the join
--     screen can show the pending invitation and the business name)
--   * self-activation UPDATE policy + a guard trigger so a non-owner can flip ONLY
--     their own pending invitation to active (never permissions/is_owner/display_name)
--   * a BEFORE INSERT trigger on business_members linking user_id when the invited
--     email already has an auth account (status stays 'invited' — the user accepts
--     explicitly on the join screen, spec §4.0 step 4)
--   * a backfill repairing invited rows created before this migration
--
-- New-signup behaviour is unchanged: trg_activate_pending_invites still auto-activates
-- the membership when the invited email signs UP (spec §3).

-- ============ HELPERS ============

-- The calling user's email claim from the JWT, lowercased ('' when absent).
create or replace function auth_email()
returns text
language sql
stable
as $$
  select lower(coalesce(auth.jwt() ->> 'email', ''));
$$;

-- Pending-invite check: the caller has an un-accepted invitation to this business,
-- matched by linked user id or (while unlinked) by invited email. security definer so
-- policies on OTHER tables (businesses) can consult business_members without recursing
-- through its RLS — same pattern as is_active_member/is_owner/has_perm in 002.
create or replace function is_invited_member(biz uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from business_members m
    where m.business_id = biz
      and m.status = 'invited'
      and m.deleted_at is null
      and (
        m.user_id = auth.uid()
        or (m.user_id is null and lower(m.invited_email) = auth_email())
      )
  );
$$;

-- ============ POLICIES (permissive — OR'd with the 002 baseline) ============

-- Invitee can SEE their own pending invitation.
create policy business_members_select_invited_self on business_members
  for select using (
    status = 'invited'
    and deleted_at is null
    and (
      user_id = auth.uid()
      or (user_id is null and lower(invited_email) = auth_email())
    )
  );

-- Invitee can see the business they were invited to (join screen shows its name).
create policy businesses_select_invited on businesses
  for select using (is_invited_member(id));

-- Self-activation: the invitee may update ONLY their own pending invitation, and the
-- resulting row must be their own ACTIVE, non-owner membership. Field-level integrity
-- (permissions/display_name/... unchanged) is enforced by the guard trigger below —
-- WITH CHECK cannot compare OLD to NEW.
create policy business_members_update_self_activation on business_members
  for update using (
    status = 'invited'
    and deleted_at is null
    and (
      user_id = auth.uid()
      or (user_id is null and lower(invited_email) = auth_email())
    )
  )
  with check (
    user_id = auth.uid()
    and status = 'active'
    and is_owner = false
    and deleted_at is null
  );

-- ============ GUARD: a non-owner update may ONLY self-activate ============
-- RLS decides WHICH rows a non-owner can update; this trigger pins WHAT may change:
-- exactly invited -> active on their own row, with every owner-controlled field
-- (permissions, display_name, is_owner, invited_email, business_id) untouched.
create or replace function guard_member_self_activation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Owner-managed paths and server-side paths (service role, auth triggers — no JWT
  -- uid) stay unrestricted.
  if auth.uid() is null or is_owner(old.business_id) then
    return new;
  end if;
  if old.status <> 'invited'
     or new.status <> 'active'
     or new.user_id is distinct from auth.uid()
     or new.business_id <> old.business_id
     or lower(new.invited_email) <> lower(old.invited_email)
     or new.display_name <> old.display_name
     or new.is_owner <> old.is_owner
     or new.permissions <> old.permissions
     or new.deleted_at is not null
  then
    raise exception 'business_members: only self-activation of your own invitation is allowed';
  end if;
  return new;
end;
$$;

create trigger trg_guard_member_self_activation
  before update on business_members
  for each row execute function guard_member_self_activation();

-- ============ LINK EXISTING AUTH USERS AT INVITE TIME ============
-- Mirror of trg_activate_pending_invites for the opposite ordering: the auth account
-- already exists when the owner creates the invite. Links user_id (making the row
-- visible to the invitee under the baseline user_id = auth.uid() policy too) but keeps
-- status 'invited' — the invitee accepts explicitly on the join screen.
create or replace function link_invited_member()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_user uuid;
begin
  if new.status = 'invited' and new.user_id is null then
    select u.id into existing_user
    from auth.users u
    where lower(u.email) = lower(new.invited_email)
    limit 1;
    if existing_user is not null then
      new.user_id := existing_user;
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_link_invited_member
  before insert on business_members
  for each row execute function link_invited_member();

-- ============ BACKFILL ============
-- Repair invited rows created before this migration for users whose auth account
-- already existed (the auth.users trigger never re-fires for them).
update business_members m
   set user_id = u.id
  from auth.users u
 where m.status = 'invited'
   and m.user_id is null
   and m.deleted_at is null
   and lower(u.email) = lower(m.invited_email);
