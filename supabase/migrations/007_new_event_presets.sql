-- 007_new_event_presets.sql — add the '⭐ Lagan' and '👰🏻‍♀️ Muh Dikhayi' presets.
--
-- event-types.json (the seed template) gained two new built-in presets after
-- migration 006 seeded the original 7. New businesses get them client-side
-- from the template; this migration backfills them for every EXISTING
-- non-deleted business, following 006's conventions (English labels — the
-- template's canonical locale; colors are keys from booking-colors.json;
-- sort_order continues the template order after 'Custom' at 6).
--
-- RE-RUN / CONFLICT SAFETY
--   The insert anti-joins on lower(label) per business, so it is a no-op for
--   any business that already has a preset with the same name (case-
--   insensitive) — whether from a previous run of this migration or created
--   by the user. The anti-join deliberately ignores deleted_at: if a user
--   ever tombstoned a same-named preset, we do NOT resurrect it.

insert into event_types (business_id, label, icon, color, sort_order)
select b.id, s.label, s.icon, s.color, s.sort_order
from businesses b
cross join (
  values
    ('Lagan',       '⭐', 'peacock', 7),
    ('Muh Dikhayi', '👰🏻‍♀️', 'fuchsia', 8)
) as s(label, icon, color, sort_order)
where b.deleted_at is null
  and not exists (
    select 1
    from event_types et
    where et.business_id = b.id
      and lower(et.label) = lower(s.label)
  );
