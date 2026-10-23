# Assistant context contract (Android `onProvideAssistContent`)

**Status:** contract, 2026-10-23. Android implements it in the activity hosting the app shell;
web is not involved (browsers already expose the page URL). Both platforms' Help screens and
the public help site read the same `help/guide.json`, so the context Android hands to the
assistant always points at content identical to the in-app Help.

## Why

The owner summons Gemini over any screen of the Android app and asks "how do I record a
payment here?". Android's `Activity.onProvideAssistContent(AssistContent)` lets the app
tell the assistant **which screen is open** and hand it a **public URL** plus **structured
data**. Gemini can then fetch the matching help page (GitHub Pages, no auth) and answer with
the exact button names for the current language.

## What Android sends

```kotlin
override fun onProvideAssistContent(outContent: AssistContent) {
    super.onProvideAssistContent(outContent)
    val ctx = assistContextProvider.current()        // see "Resolution" below
    outContent.webUri = Uri.parse(ctx.pageUrl)
    outContent.structuredData = ctx.jsonLd            // ≤ 8 KB, see "Size cap"
}
```

### 1. `setWebUri` - the help page for the current screen + app language

```
https://itsluminous.github.io/samaroh-shared/help/<lang>/<screenId>.html
```

- `<lang>` = the **app's** current language (`hi` | `en`), not the device locale.
- `<screenId>` = the guide screen id for the visible destination (mapping below).
- Unknown / unmapped destination → the index page
  `https://itsluminous.github.io/samaroh-shared/help/<lang>/index.html`.
- Build the URL from `help/guide.json` → `site.baseUrl` + `site.pagePattern`; never hard-code
  the host in the app.

### 2. `setStructuredData` - JSON-LD

```json
{
  "@context": "https://schema.org",
  "@type": "WebPage",
  "name": "बुकिंग कार्ड",
  "description": "एक बुकिंग का पूरा विवरण: …",
  "url": "https://itsluminous.github.io/samaroh-shared/help/hi/booking_card.html",
  "inLanguage": "hi",
  "samaroh": {
    "screenId": "booking_card",
    "language": "hi",
    "app": "android",
    "guideIndexUrl": "https://itsluminous.github.io/samaroh-shared/help/hi/index.html",
    "tasks": [
      {
        "id": "record_payment",
        "title": "ग्राहक से मिला भुगतान दर्ज करें",
        "steps": [
          "कैलेंडर से बुकिंग कार्ड खोलें।",
          "भुगतान दर्ज करें दबाएँ (फ़ोन पर: कार्ड के नीचे रुपये ₹ का चिह्न)।",
          "…"
        ]
      }
    ]
  }
}
```

- `name`, `description` = the screen's `title[lang]`, `summary[lang]` from `guide.json`.
- `samaroh.tasks` = that screen's tasks, **steps filtered to `platforms` containing
  `android`** (steps without `platforms` are included), text in `lang` only. Omit
  `keys`/`permission`; optionally drop tasks whose `permission` the current member lacks.
- `samaroh.app` is always `"android"` here (reserved for a future web mirror).
- Serialize compactly (no pretty-printing).

### What is NEVER sent

- No customer names, phone numbers, amounts, invoice numbers, party names, item names,
  note contents, file names, member emails - nothing from the user's data.
- No ids of records (booking id, party id), no business name, no sign-in state.
- Only guide text (already public) plus the screen id and language.

The `AssistContent` is read by whatever assistant the user has set as default; treat it as
leaving the device.

### Size cap

Target **≤ 8 KB** for the structured data string (`AssistContent` rides in a Bundle; keep it
small so it never approaches the binder limit and Gemini ingests it in full).
Implementation: serialize; if `length > 8 * 1024`, drop step text (`steps: []`) from the
tasks at the end of the list one by one, then drop whole tasks from the end, until it fits.
`name`, `description`, `url` and `samaroh.screenId/language/guideIndexUrl` are never
dropped. The guide pages themselves have no cap - the URL always carries the full content.

### Resolution: destination → `screenId`

The nav host exposes the current destination; map it to a guide id. Unknown → `null` →
index page. Keep this table in the app next to the provider and update it when `guide.json`
gains a screen.

| Android destination (route / sheet) | `screenId` |
|---|---|
| `booking/calendar` (month or events view, no sheet) | `booking_calendar` |
| `booking/calendar` with the booking card sheet open | `booking_card` |
| `booking/calendar` with the record-payment sheet open | `record_payment` |
| `booking/form…` | `booking_form` |
| `expenses/home`, `expenses/share_pick` | `expenses_home` |
| `expenses/add_person` | `expenses_home` (task `add_party`) |
| `expenses/ledger/{partyId}` | `expenses_ledger` |
| `expenses/entry/…`, `expenses/entry_for_booking/…` | `add_expense` |
| `inventory/home` showing current stock | `inventory_stock` |
| `inventory/home` showing the item list | `inventory_masterlist` |
| `inventory/item/{id}` | `inventory_item` |
| `notes` | `notes` |
| `files` | `files` |
| `menu_home` | `menu` |
| `menu_settings`, `menu_settings_language`, `menu_settings_sync`, `menu_settings_business`, `menu_settings_event_types`, `menu_settings_reminders`, `sync_status` | `settings` |
| `menu_members` | `members` |
| `menu_about` | `menu` |
| `reports_home`, `reports_detail/…` | `reports` |
| `onboarding…` | `sign_in` |
| anything else | `null` → index page |

Sheets/dialogs are part of the screen state, not the nav graph - the provider must ask the
visible screen's view-model which sheet is open (booking card vs. record payment) before
falling back to the route.

### Refresh timing

`onProvideAssistContent` is called when the assistant is invoked, so the provider just reads
the current state; no caching needed. Compute the JSON lazily (only when asked) and off the
main thread is unnecessary at 8 KB.

## In-app Help screen (both platforms)

Menu → *Help* (new row; key to be added to the menu fragment) renders `guide.json` in the app
language: the screen list, then tasks with numbered steps, filtered to the current platform.
Each screen page shows a "share" action with the Pages URL so the owner can send a help link
over WhatsApp. The in-app Help needs no network - the guide ships in the submodule.

## Testing checklist (Android)

- Open a booking card in Hindi, summon Gemini: it should receive
  `…/help/hi/booking_card.html` and JSON-LD with `screenId: "booking_card"`.
- Switch language to English and repeat: URL and texts switch to `en`.
- Open an unmapped debug screen: URL is the `index.html` of the current language.
- Assert with a unit test that the serialized JSON never contains the strings of the
  current booking's customer name / phone / amount (feed a fixture booking and grep).
- Assert the size cap: a guide screen with artificially long steps serializes to ≤ 8192 chars.
