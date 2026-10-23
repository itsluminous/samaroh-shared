# help/ - the single-source user guide

Everything a user (and Gemini) needs to know about *how to do a task* in Samaroh lives in
**one** file, `help/guide.json`. Four consumers read it and nothing else:

| Consumer | How |
|---|---|
| Android in-app Help screen | reads `guide.json` from the `shared/` submodule at build time |
| Web `/help` route | same, via the `shared/` submodule |
| Public help site (GitHub Pages) | `.github/workflows/pages.yml` → `scripts/build-help-site.mjs` |
| Gemini (Saved info + Gem knowledge, and per-screen context from Android) | `help/gemini/*`, `help/guide.{en,hi}.md`, `docs/assistant-context.md` |

Rules: button names are written **exactly as the string catalog spells them** and every step
that names a button lists the catalog keys it used (`keys`), so the validator can refuse
wording that drifts from the real UI. Plain language, real Hindi, no customer data.

## Files

```
help/guide.json          THE guide (schema below)
help/routes.json         allowed deepLink ids → Android route / web path
help/guide.en.md         generated: node scripts/export-help-markdown.mjs  (Gem knowledge file)
help/guide.hi.md         generated, same
help/gemini/saved-info.en.md   paste-ready Gemini "Saved info" entries (English)
help/gemini/saved-info.hi.md   same, Hindi
help/gemini/gem-instructions.md  how to set up the "Samaroh helper" Gem
```

Scripts: `scripts/validate-help.mjs` (CI-blocking), `scripts/export-help-markdown.mjs`
(`--check` is CI-blocking), `scripts/build-help-site.mjs` (static site, used by Pages).

## `guide.json` schema (version 1)

```jsonc
{
  "version": 1,
  "languages": ["en", "hi"],              // must include en + hi; every text has both
  "site": {
    "baseUrl": "https://itsluminous.github.io/samaroh-shared/help/",   // https, trailing /
    "pagePattern": "{baseUrl}{lang}/{screenId}.html",
    "indexPattern": "{baseUrl}{lang}/index.html"
  },
  "screens": [
    {
      "id": "booking_card",                 // stable snake_case; NEVER rename (it is a public URL
                                            // and the Android/web screen→help mapping key)
      "title":   { "en": "…", "hi": "…" },
      "summary": { "en": "…", "hi": "…" },  // 1-3 plain sentences: what this screen is
      "deepLink": "booking/card",           // an id from help/routes.json
      "permission": "booking.view",         // optional: <section>.<capability> from
                                            // permissions/permissions-schema.json
      "platforms": ["android", "web"],      // optional; omit = both
      "tasks": [
        {
          "id": "record_payment",           // snake_case, unique within the screen
          "title": { "en": "…", "hi": "…" },
          "deepLink": "booking/card",       // where the app should land to start the task
          "permission": "booking.record_payment",   // optional gate
          "platforms": ["android"],         // optional; omit = both
          "steps": [
            {
              "en": "Tap Record payment (on the phone: the rupee ₹ icon …).",
              "hi": "भुगतान दर्ज करें दबाएँ (फ़ोन पर: रुपये ₹ का चिह्न …)।",
              "keys": ["booking.card.action_record_payment"],   // optional: catalog keys whose
                                            // labels appear verbatim in BOTH texts (validated)
              "platforms": ["android"]      // optional: step applies only on these platforms
            }
          ]
        }
      ]
    }
  ]
}
```

Step ordering **is** the numbering. A step restricted with `platforms` is shown only on that
platform (the site and the Markdown export tag it "phone" / "web"); every platform a task
targets must keep at least one applicable step.

### Stable screen ids (current)

`app_shell`, `booking_calendar`, `booking_form`, `booking_card`, `record_payment`,
`expenses_home`, `expenses_ledger`, `add_expense`, `inventory_stock`, `inventory_masterlist`,
`inventory_item`, `notes`, `files`, `menu`, `settings`, `members`, `reports`, `sign_in`.

Android maps its current destination to one of these ids (fallback: the index page) when it
provides assistant context - see `docs/assistant-context.md`. Add a new id when a genuinely
new screen appears; otherwise add tasks to the existing screen.

## `routes.json` - deepLink ids

`deepLink` values are platform-neutral ids; `routes.json` resolves each to the Android nav
route (as declared in the feature `*NavGraph.kt` files) and the web path (locale prefix
omitted). `null` means that platform has no equivalent (e.g. `menu/settings/reminders` is
Android-only). The validator refuses a guide entry restricted to a platform whose route is
`null`. `{argument}` segments are filled by the app when it knows them; otherwise it opens
the parent list screen.

## Validation (`scripts/validate-help.mjs`)

1. shape + `version: 1`; languages include `en` and `hi` and have catalogs
2. ids snake_case, unique
3. en/hi parity on every text; Hindi text must contain Devanagari
4. `keys` exist in the canonical catalog, are translatable, and - for labels without ICU
   placeholders - appear verbatim in the step text of **each** language
5. every `deepLink` is in `routes.json`; `platforms` ⊆ {android, web} and compatible with the route
6. every `permission` is `<section>.<capability>` in `permissions/permissions-schema.json`
7. no PII / sample data: phone numbers, emails, ₹ amounts, `{name}`-style placeholders

Run before every commit together with the catalog validator and `scripts/legal-check.sh`:

```bash
node scripts/validate-catalogs.mjs && node scripts/validate-help.mjs \
  && node scripts/export-help-markdown.mjs --check && bash scripts/legal-check.sh
```

## Public help site - decision (2026-10-23)

**Problem.** Gemini (and any crawler) must be able to fetch the guide over plain HTTPS.
The web app's only known host is `samaroh-web.vercel.app` (no custom production domain is
configured anywhere in `samaroh-web` - README/AGENTS/vercel.json only mention the
`*.vercel.app` URL). That host is a Vercel deployment whose protection setting can put
every path behind Vercel SSO, and even when open it serves a sign-in page for
unauthenticated visitors. A `/help` route there would be fragile for an assistant.

**Decision.** Host the help site from **this** repo on **GitHub Pages**:

- stable, public, no auth, no cookies: `https://itsluminous.github.io/samaroh-shared/help/<lang>/<screenId>.html`
- built on every push to `main` by `.github/workflows/pages.yml` from `guide.json` - the same
  file the apps bundle, so the site can never say something different from the in-app Help
- pure static HTML with JSON-LD (`WebPage` + `HowTo`) so Gemini gets structured steps
- `help/guide.json`, `help/routes.json` and the `.md` exports are published alongside

The web app's `/help` route should render the same `guide.json` in-app and link to the
Pages URL for sharing; it does not need to be public.

### One-time setup (owner, if the API call in the delivery did not stick)

GitHub → repo **samaroh-shared** → **Settings** → **Pages** → *Build and deployment* →
**Source: GitHub Actions**. Nothing else; the workflow handles the rest. Re-run the
"Help site (GitHub Pages)" workflow from the Actions tab if the first deploy predates the
setting.

## Authoring guidance

- Write for a 60+ owner: one action per step, name the button, say where it is ("bottom
  right", "top right").
- Android action buttons are icons: say "(on the phone: the ₹ icon)" and rely on the long-press
  tip the site shows on every page.
- Prefer the label the app shows; when Android and web labels differ, write two steps with
  `platforms`.
- Hindi: everyday words (बाकी, मिल चुका, दबाएँ), not formal Sanskritised Hindi; keep English
  technical words the UI keeps (UPI, PDF, WhatsApp, Google Drive).
- Never put customer names, phone numbers or amounts in examples; the validator rejects them.
