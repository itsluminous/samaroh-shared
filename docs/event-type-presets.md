# Event-type presets: database-backed, plain-text labels

Migration `006_event_types.sql` moves booking event-type presets from static
config (`event-types.json`) into the per-business `event_types` table so users
can add, edit, reorder and delete their own presets.

## Decision: labels are plain text, no longer localized

Until 006, event-type display names were string-catalog keys
(`booking.event_type.*`) resolved per-locale at render time — an English user
saw "Wedding", a Hindi user saw "शादी" for the same booking.

Now `event_types.label` is **plain-text user data**, exactly like a customer
name or a party name. Whatever text the row holds is what every member sees,
in every app language. The `booking.event_type.*` catalog keys stay for
rendering the recorded type of *old* bookings whose `event_type` is still a
built-in key, but new presets never go through the catalog.

Why: user-created presets cannot be localized (we can't translate arbitrary
names), so a mixed model — some presets localized, some not — would be
inconsistent and force clients to keep two rendering paths for the same
picker. One rule ("the label is the label") is simpler and matches how the
rest of the product treats user-entered text.

## Tradeoff: existing businesses are seeded in English

Migration 006 seeds the 7 built-ins for every existing business with their
**English** labels (Engagement, Tilak, … Custom), because a server-side
migration has no way to know each business's preferred app language. A
Hindi-locale user of a pre-006 business will see English preset names until
they rename them — that is the accepted cost of the plain-text model.

Mitigation: seeding for **future** businesses is client-side at business
creation (the app inserts the presets from `event-types.json`, the seed
template), so a client *may* seed in the device's current language.

## What deleting a preset means

`bookings.event_type` / `bookings.event_icon` remain recorded free text —
bookings do not reference `event_types` rows. Deleting a preset soft-deletes
the row (`deleted_at`); existing bookings keep their recorded type and icon
unchanged. The delete confirmation string
(`settings.event_types.delete_message`) says exactly this.

## Uniqueness

Live preset names are unique per business via a partial unique index
(`uq_event_types_biz_label` on `(business_id, label) where deleted_at is
null`) — a deleted preset's name can be reused. Clients surface violations
with `settings.event_types.duplicate_name`.
