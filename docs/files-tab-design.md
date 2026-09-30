# Files tab — design & shared contract (2026-09-29)

**Status:** decided. This is the cross-platform contract for the FILES module; the
Android and web implementers build against it in parallel. Server side:
`supabase/migrations/009_files_tab.sql` + `010_files_rename_move.sql` (rename/move,
2026-09-30; both validated by 001→010 + seed replay and RLS probes on scratch Postgres 15).
Strings: `strings/fragments/files.{en,hi}.json` (105 keys).
Permissions: `files` module in `permissions/permissions-schema.json`.

Owner requirement (verbatim): *"A Files tab which behaves like file storage proxying to
the Samaroh Google Drive folder. Create folders, upload files (images, pdf, anything).
Search bar. Access controlled for view/upload/delete. If possible folder-level access
control. When a user shares media to Samaroh via share sheet, ask: inventory or file
upload. Parity web+android with tests."*

---

## 0. Decision list (the contract, one line each)

| # | Topic | Decision |
|---|---|---|
| D1 | Data model | Three Supabase tables: `folders`, `files`, `folder_access` — a **metadata index**; bytes live in Google Drive. All three are **mutable rows with `updated_at`** (tombstone bumps the LWW cursor → single pull leg; NOT the immutable `expense_attachments` shape that needed ADR-084's second leg). |
| D2 | `folders` | `id, business_id, parent_id (NULL = top level), name, restricted, created_by, updated_by, created_at, updated_at, deleted_at`. **No `drive_folder_id`** (see D4 — there is no single Drive folder per app folder). |
| D3 | `files` | `id, business_id, folder_id (NULL = top level), name, mime_type, size_bytes, drive_file_id NOT NULL, created_by, created_at, updated_at, deleted_at`. No link/thumbnail columns: every URL is derived from `drive_file_id`. |
| D4 | Drive layout | Bytes go to the **uploader's own Google Drive** (`drive.file` scope, exactly like bills ADR-018/059 and item photos ADR-063) at `Samaroh/{Business Name}/files/{Folder}/{Sub folder}/{file name}` — a **best-effort human-readable mirror** of the app hierarchy created find-or-create at upload time. Each file gets an **anyone-with-link reader permission** inline (ADR-059 posture) so every member (and the web, signed-in or not) can open it. The app's metadata index is authoritative; Drive is never listed or reconciled. |
| D5 | Permission keys | New module `files` with `view`, `upload`, `manage_folders`, `delete`. `manage_folders` ABSENT **inherits `upload`** (`coalesce(manage_folders, upload, false)`, `has_files_perm()` server-side, the 007 notes pattern; explicit false never falls through). Everything else absent = false. |
| D6 | Folder-level access | **Restricted folders (allow-list model).** `folders.restricted=true` ⇒ only the owner + members with a live `folder_access(folder_id, member_id)` row see the folder **and its whole subtree**. Nested restrictions intersect (you must pass EVERY restricted ancestor). Root is never restricted. **Owner-only** to flip `restricted` / edit `folder_access` (guard trigger + RLS). `folder_access` narrows `files.view`; it never grants. |
| D7 | Presets | Viewer = `view`; Staff = `view + upload` (+ `manage_folders` materialized true, the inherited value); Manager = all four. **No server-side backfill** of existing members (absent = false → module hidden until the owner grants it; same launch posture as notes/005). An opt-in backfill snippet lives in the owner DDL handoff. |
| D8 | Upload path for non-owners | Same as bills today: **each uploader uses their own linked Google account**; files land in *their* Drive, shared anyone-with-link, indexed in Supabase. Unlinked users: the Upload button is **shown** (permission-gated only) and tapping it opens the **"Connect Google Drive" prompt** (Android: the ADR-049 real link flow; web: Google consent popup). Android additionally stages the file locally and queues it (outbox, `files.upload.pending_unlinked`) so nothing is lost. |
| D9 | Web Drive access | **Web gains a browser-side Google Drive client**: Google Identity Services token client, `https://www.googleapis.com/auth/drive.file`, using the SAME Web-application OAuth client id Android already uses (`NEXT_PUBLIC_GOOGLE_WEB_CLIENT_ID`; owner adds the site origins as Authorized JavaScript origins). Access token in memory/sessionStorage, silent re-request on expiry, consent popup on first use. Build/run must still succeed without the env var (→ `files.upload.not_configured`). Web uploads are **online-only** (bytes are not queued); folder create/rename/delete and tombstones go through the Dexie outbox as usual. |
| D10 | Deletion contract | ADR-053/084 reused: **metadata tombstone (UPDATE `deleted_at`) is authoritative and syncs; Drive `files.delete` is best-effort**, attempted only when the actor is linked, non-fatal, 403/404 (not my file) swallowed. Deleting a folder tombstones its subtree client-side (children first, one outbox op each — ADR-028 cascade style) and best-effort deletes the Drive files the actor owns. No server-side cascade. Requires `files.delete`. |
| D11 | Search | **Global**: the search field on the Files screen searches ALL folders + files of the business the member can access (case-insensitive name substring), results flat with a path subtitle (`files.search.result_path`). Empty query = current folder listing. Android: Room query; web: client filter over the fetched index (PostgREST `ilike` acceptable). |
| D12 | Naming / conflicts | Folder names unique per parent per business, **case-insensitive, LIVE rows only** (partial index over `lower(name)`, the 008 lesson); 1–120 chars, no `/`. File names may **repeat** (Drive allows it; camera exports collide); 1–255 chars, no `/`; the display name = original file name incl. extension; Drive gets the same name. |
| D13 | Limits | **25 MiB per file** (server CHECK `size_bytes ≤ 26214400`; client rejects with `files.upload.too_large`). **20 files per batch** (`files.upload.too_many`). Folder depth ≤ 10 (client), RLS chain cap 64. Any MIME accepted. **Images are NOT recompressed** (this is file storage — originals). |
| D14 | Rename / move | *Revised 2026-09-30 (owner feedback on the 0.18 drop; shared migration `010_files_rename_move.sql`).* **Folder rename** (`files.manage_folders`; Drive folder renamed best-effort). **File rename** (new): the `files_update` policy verbatim — `files.delete` OR (`files.upload` ∧ `created_by = me`); owners always; Drive file name patched best-effort. **Move (file AND folder)**: `folder_id` / `parent_id` are now mutable via UPDATE. Files: same gate as file rename; folders: `files.manage_folders`. Guard trigger (010) refuses cycles (destination = self or a live descendant) for everyone and, for non-owners, requires `manage_folders` + access to the destination parent; the files policy's WITH CHECK requires access to the destination folder. Clients validate before writing: same-location, cycle, depth (destination depth + moved subtree height ≤ 10), live case-insensitive sibling-name duplicate for folders (the unique index would 23505). Metadata via the outbox (whole-row UPSERT Android / PATCH web); Drive `files.update` (`name`, `addParents`/`removeParents` onto the find-or-create mirror chain) best-effort — linked actor only, 403/404 swallowed, exactly the D10 delete posture. Rows renamed/moved on Drive by hand are never reconciled (the index stays authoritative). |
| D15 | Tab placement | Files is a **top-level module** (own route/graph, deep link `/files`, `files.nav.tab`, bar icon `Folder`). Module order: Booking, Expenses, Inventory, Notes, **Files**. **Bottom bar = visible modules ONLY, cap 5** (Material 3's 5-item limit = all five modules; *revised 2026-09-29 on owner feedback* — originally "4 + Menu" with a Menu → More overflow). **The Menu is NOT a bar tab: it lives behind a title-bar kebab (⋮) placed immediately RIGHT of the sync indicator** (a11y label `common.nav.menu`) and opens the unchanged Menu screen (search, identity row, Settings, Reports, Members [owner], About). A module the member cannot `view` is hidden (not greyed) and the bar simply has one fewer item; **no viewable module → no bar at all** and the shell starts on the Menu. Same on Android and web-mobile (xs–sm); web **desktop** (md+) keeps the left rail with every visible module + Menu as the LAST rail entry and no kebab. Android hides the kebab while the Menu is open (it would stack a second Menu); web keeps it tinted/`aria-current` on `/menu` as the "you are here" cue (no nav stack). `files.nav.more_section` stays in the catalog: web-mobile keeps an inert overflow split for a hypothetical 6th module; Android removed its overflow machinery. |
| D16 | Open behaviour | Tap image → in-app viewer (Android `ImageViewerDialog`, web lightbox — public thumbnail ladder `drive.google.com/thumbnail?id=…&sz=w1600` → `lh3` fallback). **Tap anything else — Android (*revised 2026-09-30*): resolve the BYTES exactly like an expense bill (staged original → `files-cache/` via the `DriveFileFetcher` own-token→public ladder) and hand the local file to the system via the module's `FileProvider` + `ACTION_VIEW` with the row's MIME (chooser; `files.file.no_viewer_app` when nothing can display the type). NEVER an implicit `VIEW` on a `drive.google.com` URL: the Google Drive app owns that host as a verified App Link, captures the intent and demands an account every time (the 0.18 bug). Web: Drive viewer `https://drive.google.com/file/d/{id}/view` in a new tab.** "Open in Google Drive" stays an explicit action and, on Android, pins the Custom Tab to a browser package. Thumbnails: images + PDFs via `thumbnail?id=…&sz=w320` (web) / `DriveFileFetcher` own-token→public download into a `files-cache/` (Android, images only); other MIMEs show a type icon. |
| D17 | Actions | Long-press (Android) / kebab (web) on a file: Open, Open in Google Drive, Download, Copy link, **Rename** (`files.action.rename_file`), **Move to…** (`files.action.move`), Delete. On a folder: Rename, **Move to…**, Delete, Manage access (owner only). **Permission-hidden, never greyed** (ADR-038); gates per D14. |
| D18 | Share sheet (Android) | ONE share target alias labelled **"Save to Samaroh"** (`files.share_target.label`) accepting `ACTION_SEND` + `ACTION_SEND_MULTIPLE`, `*/*`. It opens a **chooser**: *Create invoice* (existing ADR-078 flow; single image/PDF; `expenses.create`), *Set as item photo* (single image; `inventory.manage_master_items`; opens the existing edit-item dialog with the photo pre-staged), *Save to Files* (anything, multiple; `files.upload`; folder picker, top level preselected, **with a "New folder" row** — see §7). Rows are permission-hidden; none left → `files.share_target.no_options`. The existing `.CreateInvoiceShareTarget` alias is **replaced** by the new one. Web: drag-and-drop onto the folder view + multi-file picker; uploads started from a NON-folder context (global search results) go through the same destination picker (`files.picker.confirm`, `files.picker.selected_hint`, `web-files` fragment). |
| D19 | Sync spec | Android `SyncTables`: `folders` (business-scoped, `updated_at` cursor), `files` (same), `folder_access` (composite PK `folder_id|member_id`, `idColumn2`, soft link like `note_tag_links`). Web: all three through `insertWithOutbox`/`updateWithOutbox`; `folder_access` uses the composite `match` locator. Files rows are pushed **only after** the Drive upload succeeded (Android: upload-before-row-push exactly like bills, `FilesUploader` in `core:google`). |
| D20 | Backup | Drive backup (Android) **exports** `folders`, `files`, `folder_access` rows (metadata) and adds `files.drive_file_id` to the attachment manifest; `BackupExporter.BUSINESS_SCOPED_TABLES` grows by three and `BackupExporterSchemaGuardTest` expects them; `docs/backup-format.md` updated. |
| D21 | Room | Android Room migration **12→13**: entities `folders`, `files`, `folder_access` (+ device-only `files.local_cache_path`, `files.drive_permission_ensured` like bills; `LocalApplier` preserves them across pulls). |
| D22 | ADRs | Android: **ADR-085** "FILES module: Drive-indexed file storage, restricted folders, nav overflow rule (shared migration 009)"; **ADR-086** "Unified share target: Save to Samaroh chooser (invoice / item photo / Files)"; **ADR-087** "Menu becomes title-bar overflow (kebab); Files takes its bottom slot; picker New folder" (supersedes the ADR-085 overflow rule). Web decisions.md: "2026-09-xx — FILES section (shared migration 009) + nav overflow rule", "2026-09-xx — Browser-side Google Drive linking (GIS `drive.file`) for Files uploads" and "Web chrome feedback batch" (kebab, Files in bar, folder picker, sign-out only on Menu). |

---

## 1. Why a metadata index over Drive (and not Drive listing or Supabase Storage)

- The codebase already treats Drive as **the** blob store for everything except the
  business logo (Android ADR-065; web "image architecture convergence"), with Supabase
  holding metadata rows behind RLS. Files follows that exact posture.
- Listing Drive directly is impossible for members: `drive.file` only sees files *this
  app on this account* created; another member's uploads are invisible to your token
  (ADR-059 context). The index makes the module look like ONE shared storage while the
  bytes are spread over the uploaders' Drives.
- The index is what gives offline listing (Android Room), search, permissions (RLS),
  restricted folders and sync for free via the existing outbox/pull machinery.

### Honest limitations (documented, accepted)

- "The Samaroh Google Drive folder" is *logically* one (the index) but *physically* one
  tree per uploader. For the common case (owner uploads) everything is in the owner's
  Drive under `Samaroh/{Business}/files/…`.
- A revoked member's uploads stay in *their* Drive; the anyone-with-link permission keeps
  them openable; the owner can only tombstone the row (Drive delete 403s → swallowed) —
  same as bills today (ADR-053 consequences).
- Renames/moves are mirrored into Drive only best-effort (D14: linked actor, own bytes,
  403/404 swallowed); Drive ids are stable so nothing breaks. Drive is a mirror for humans
  browsing Drive, never the source of truth.
- Threat model = ADR-059 §4 verbatim: anyone WITH a file's link can open it; ids are
  high-entropy, discovery is off, ids live behind RLS. Copy-link exposes exactly one file.

## 2. Data model (see `009_files_tab.sql` for the authoritative DDL)

```
folders        id, business_id, parent_id?, name, restricted, created_by, updated_by,
               created_at, updated_at, deleted_at
               uq_folders_biz_parent_name (business_id, coalesce(parent_id, nil-uuid), lower(name)) WHERE deleted_at IS NULL
files          id, business_id, folder_id?, name, mime_type, size_bytes (0..25 MiB), drive_file_id NOT NULL,
               created_by, created_at, updated_at, deleted_at
folder_access  PK (folder_id, member_id→business_members.id), business_id, created_at, updated_at, deleted_at
```

Row-level rules the clients mirror:

- `folder_id`/`parent_id` NULL = top level ("All files", `files.home.root_label`).
- A file under a tombstoned folder is hidden client-side (no server cascade).
- `files.drive_file_id` is NOT NULL: **a server row is always openable**. Android keeps
  locally staged, not-yet-uploaded files in Room with a device-only marker and the outbox
  entry; the row reaches the server only after upload (identical to bills).
- Derived URLs: view `https://drive.google.com/file/d/{id}/view`; thumbnail
  `https://drive.google.com/thumbnail?id={id}&sz=w{px}` (fallback
  `https://lh3.googleusercontent.com/d/{id}=w{px}`); download
  `https://drive.google.com/uc?export=download&id={id}` (HTML-interstitial guard, ADR-059).

## 3. Permissions & RLS

Helpers: `has_files_perm(biz, action)` (inheritance `manage_folders → upload`),
`can_access_folder(biz, folder_id)` (recursive ancestor walk, owner bypass, NULL = true),
`is_my_member_row(member_id)`.

| Table | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|
| folders | `view` ∧ access(id) | `manage_folders` ∧ access(parent) ∧ `created_by = uid` ∧ (¬restricted ∨ owner) | (`manage_folders` ∨ `delete`) ∧ access(id); guard (010): non-owner can't change `restricted`; `deleted_at` needs `delete`; `name` and `parent_id` need `manage_folders`; `parent_id` change also needs access(new parent) and is cycle-guarded for everyone | `delete` ∧ access |
| files | `view` ∧ access(folder) | `upload` ∧ access(folder) ∧ `created_by = uid` | access(old) ∧ access(new folder) ∧ (`delete` ∨ (`upload` ∧ `created_by = uid`)); guard (010): `drive_file_id`/`mime`/`size` immutable for all, `name` + `folder_id` mutable; `deleted_at` needs `delete` | `delete` ∧ access |
| folder_access | owner ∨ row names me | owner | owner | owner |

Why the uploader may UPDATE their own file: PostgREST upsert (`ON CONFLICT DO UPDATE`)
evaluates the UPDATE policy when the row already exists — an outbox **retry** after a
timed-out-but-successful push would otherwise 403 forever for a Staff member. The guard
trigger makes that path a no-op beyond `name`.

Client normalization (both apps, MUST match the DB byte-for-byte):
`view = files.view === true`, `upload = files.upload === true`,
`manage_folders = files.manage_folders ?? files.upload ?? false`, `delete = files.delete === true`.
Presets materialize the inherited value so preset round-trips stay exact (web `matchingPreset`).

Restricted-folder client rules: a member sees a folder iff the server returned it (RLS
already filtered) — clients never re-derive access, except the owner's access editor
which reads `folder_access` for the whole business. Show the `Restricted` chip when
`restricted=true`. Only the owner sees *Manage access*.

## 4. Drive layout & upload pipeline

```
Samaroh/                                   (google_accounts.drive_root_folder_id)
└── {Business Name}/
    ├── backups/ … invoices/ … images/inventory/ …        (existing §9.1)
    └── files/                                            NEW (lowercase like its siblings)
        ├── {file at top level}
        └── {Folder}/{Sub folder}/{file name}             mirrors folders.name chain (sanitized: '/'→'-', trimmed)
```

- Android: `DriveTarget.Files(pathSegments: List<String>)` in `DriveLayout` →
  `folderPathBelowRoot = [business, "files", …segments]`; `RestDriveUploader` already does
  find-or-create per segment and memoizes ids. New `core:google` `DriveFilesUploader`
  implements a `FilesUploader` seam in `core:data` (mirror of `AttachmentUploader`):
  upload → `ensureAnyoneReaderPermission` (best-effort, device-only
  `drive_permission_ensured`, repair pass extended to `files`, 10 rows/run) → patch
  `drive_file_id` into the outbox payload → row push. Rows are never pushed with a null id.
- Web: `src/lib/google/drive.ts` (new) — GIS token client + REST v3 multipart upload +
  `permissions.create` + best-effort `files.delete`; folder chain find-or-create with a
  per-session memo; `google_accounts` row upserted (`drive_root_folder_id` cache shared
  with Android — RLS: own row). Concurrency: 3 uploads in flight; progress
  `files.upload.in_progress`.
- Both: original bytes, MIME from the picker (fallback `application/octet-stream`),
  `size_bytes` from the file, reject > 25 MiB before touching the network.

## 5. Sync

| Table | Android `SyncTableSpec` | Notes |
|---|---|---|
| `folders` | `SyncTableSpec("folders", businessScoped = true)` | `updated_at` keyset (default). Rename/tombstone are UPDATEs. |
| `files` | `SyncTableSpec("files", businessScoped = true, localOnlyKeys = setOf("local_cache_path", "drive_permission_ensured"))` | `updated_at` keyset. Tombstone = UPDATE (bumps cursor) — **one leg**. |
| `folder_access` | `SyncTableSpec("folder_access", businessScoped = true, idColumn = "folder_id", idColumn2 = "member_id")` | Composite PK, soft link (revoke = set `deleted_at`, re-grant = clear it on the same row). Never enqueue a DELETE op. |

Web outbox: `insertWithOutbox`/`updateWithOutbox` for all three; `folder_access` uses
the composite `match` locator and `entityId = "folderId|memberId"`. Uploads (bytes) are
online-only; if offline, the Upload action shows the offline banner state and does
nothing (no partial rows). Guest mode (Dexie v4): `folders`/`files`/`folder_access`
stores exist so folders work; upload shows `files.upload.guest_hint`.

Pull ordering is irrelevant (Room has no FKs, ADR-004; PostgREST rows are independent).

## 6. UX parity spec

**Screen.** Top app bar: title = current folder name (`files.home.title` at top level),
Up affordance (`files.breadcrumb.up`), search field (`files.home.search_placeholder`),
grid/list toggle (persisted per device). Breadcrumb row under the bar:
`All files › Contracts › 2026` (`files.breadcrumb.separator`), each crumb tappable.
Listing: folders first (A–Z, `files.folder.item_count` / `_empty` secondary line,
`Restricted` chip), then files (newest first) with thumbnail-or-type-icon, name, size
(`files.file.size_kb/mb`), `files.file.added_by`. Empty states:
`files.home.empty_*` at top level (message only for members who can upload), `files.folder.empty_title` inside.

**Primary actions.** Android: `SamarohFab` "Upload" (`files.action.upload`) + top-bar
"New folder" (`files.action.new_folder`). Web: toolbar buttons + drag-and-drop overlay
(`files.upload.drop_hint`). Both hidden by permission (`upload` / `manage_folders`).

**Upload flow.** Picker (any MIME, multiple, ≤ 20) → size check → per-file upload with a
progress snackbar → `files.upload.done`. Android offline/unlinked: files staged in Room
with `files.file.pending_label` badge; `files.upload.queued` / `files.upload.pending_unlinked`.
Unlinked + tap Upload → `files.upload.link_google_*` prompt (Connect runs the link flow,
Not now stages locally on Android / cancels on web). Web without client id →
`files.upload.not_configured`.

**Folder dialogs.** New/rename: single text field (`files.folder.name_label`),
validation `name_required` / `name_invalid` / `duplicate` (case-insensitive vs LIVE
siblings). Delete: confirm `files.folder.delete_confirm_title` +
`delete_confirm_message` (count ≥ 1) or `_empty`.

**File actions** (long-press sheet / kebab menu): Open, Open in Google Drive, Download,
Copy link, Rename (`files.file.name_label`, validation `files.file.name_required` /
`name_invalid`, snackbar `files.file.renamed`; the dialog is prefilled with the current
name INCLUDING the extension; 1–255 chars, no `/`, duplicates allowed per D12), Move to…
(see below), Delete (confirm `files.file.delete_confirm_*`). Gates per D14. Folder rename
keeps the folder-name rules (1–120, no `/`, live case-insensitive sibling uniqueness).

**Move to…** (file or folder; *reconciled 2026-09-30*). The lazy folder picker opens with
the item's CURRENT location preselected (title `files.move.title`, confirm
`files.move.confirm`, helper `files.move.selected_hint` = `Moving to: {path}`). When a
FOLDER is moved, the folder itself and its whole subtree are HIDDEN from the list (never
greyed) — it can never be its own destination; the cycle check still runs as defence.
Validation is LIVE on the current selection on both platforms: the inline error for the
selection shows at once and the Move button is disabled until a valid destination is
picked — `files.move.same_folder` (already there), `into_self` (self or a descendant),
`too_deep` (destination depth + moved subtree height > 10), `files.move.duplicate_folder`
(live case-insensitive sibling clash in the destination; folders only — file names may
repeat). Files add no depth, so a file move can only fail on same-place. Confirm writes ONE
`folder_id` / `parent_id` update via the outbox (the subtree follows by reference),
snackbar `files.move.done {folder}` (`All files` for the top level), then the best-effort
Drive re-parent (D14).

**Folder pickers** (share-sheet destination, move destination, web upload destination) are
ONE lazy-tree component: `All files` + ROOT folders only at first; rows with children carry
an expand/collapse chevron (`files.picker.expand` / `collapse` with `{name}`, web
`role=tree`/`treeitem` + `aria-level`/`aria-expanded`); children indent one level per depth
(A–Z per level); the ancestors of the preselected folder start expanded so the selection
is visible; `All files` is selectable; "New folder" (permission-hidden, depth-capped under
the selection) expands the parent and selects the created child. Sizing: compact
`body`-sized rows, near-full width on compact screens (Android `WideDialog`
`usePlatformDefaultWidth=false`, ~92% width ≤ 560 dp; web `compactDialogProps`, 8 px
gutters on `xs`). The other choosers (share chooser, name dialogs, Manage access) share the
same sizing.

**Open file** (D16). Image → in-app viewer on both. Anything else: Android resolves the
bytes and opens them with the system chooser via the module `FileProvider`
(`files.file.no_viewer_app` when nothing can display the type) — never an implicit
`drive.google.com` VIEW; web opens the Drive viewer URL in a new tab (the same URL the
expense-bill chips use). "Open in Google Drive" stays an explicit row on both.

**Manage access** (owner only, folder kebab): radio `files.access.everyone` /
`files.access.only_selected` + member checklist (display names), helper texts
`subfolders_note`, `owner_always`; saves `folders.restricted` + `folder_access` diffs;
snackbar `files.access.saved`.

**Navigation** (D15, revised 2026-09-29). Bottom bar (Android + web-mobile) = the
member's visible modules in order — Booking, Expenses, Inventory, Notes, Files — and
nothing else; Files sits in the slot the Menu used to occupy. Title bar, left → right:
business name, sync indicator, **Menu kebab** (`MoreVert`, label `common.nav.menu`). The
kebab opens the existing Menu screen (search, identity row, Settings, Reports, Members
[owner], About). Android pushes the Menu graph over the current tab (back arrow on the Menu
home, kebab hidden while inside the Menu, no bar tab highlighted, bar tap pops back); web
links to `/menu` (kebab tinted + `aria-current` there, bottom bar nothing selected).
A member with no viewable module gets no bar and lands on the Menu (Android
`NavPermissions.startDestination`, web `firstVisibleSection` → `/menu`). Web desktop (md+):
left rail with every visible module + Menu last; no kebab. Sign-out lives ONLY on the Menu
identity row on both platforms (web dropped its title-bar logout icon; the guest state
shows a **Sign in** row, `menu.identity.sign_in`). Menu search (ADR-075) no longer needs
module entries on Android; web keeps them for the (currently empty) overflow set.
Android App Links: `/{locale}/files` → Files; `/menu…` and `/reports` push the Menu the same
way the kebab does. Web: `/files` route + `SectionGuard module="files"`;
`resolveLandingHref` includes `files` in nav order.

**Permission matrix** (both apps): group `files.permission.group` with the four rows;
`manage_folders` shows the inherited value when absent (like `view_checklists`).

## 7. Share sheet (Android only) — D18 detail

1. Manifest: replace `.CreateInvoiceShareTarget` with `.ShareTarget` (alias → `MainActivity`),
   label `files.share_target.label`, filters `SEND` + `SEND_MULTIPLE` for `*/*`.
2. `ShareTargetIntents.parse` widens to a list of `(uri, mime)`; `ShareTargetHolder` holds the list.
3. Shell shows `ShareChooserDialog` (`files.share_target.chooser_title`) with rows:
   - **Create invoice** — title `expenses.share_target.label`, subtitle
     `files.share_target.option_invoice_subtitle`; only for a single image/PDF; needs
     `expenses.create`; continues into the unchanged ADR-078 party picker.
   - **Set as item photo** — `files.share_target.option_inventory(_subtitle)`; single
     image only; needs `inventory.manage_master_items`; item type-ahead picker
     (`files.share_target.pick_item_title`) → existing edit-item dialog with the photo
     pre-staged through the existing item-photo pipeline (crop → ≤320px WebP → Drive mirror).
   - **Save to Files** — `files.share_target.option_files(_subtitle)`; any MIME, any count
     (≤ 20); needs `files.upload`; folder picker (`files.share_target.pick_folder_title`,
     top level preselected, restricted folders only if accessible; **LAZY TREE** — only the
     top-level folders show at first, rows with subfolders carry an expand chevron
     (`files.picker.expand` / `files.picker.collapse`), children indent one level per depth,
     A–Z per level; *revised 2026-09-30, was a flat pre-expanded tree*) → same upload pipeline as in-app → `files.share_target.saved`.
     The picker carries a **"New folder"** affordance (`files.action.new_folder`,
     `CreateNewFolder` icon; permission-HIDDEN unless effective `files.manage_folders`
     AND the depth cap allows a child under the SELECTED row) → the standard
     `FolderNameDialog` validated against the selected parent's live siblings → the new
     folder is created (outbox) and auto-selected so the share lands in it; Android joins
     the pending folder save before staging so the share never lands in an unwritten folder.
     Web parity (no share sheet): the same picker + New folder guards uploads started from
     the global search results (`FolderPickerDialog`, confirm `files.picker.confirm`).
   Signed out / no business → `files.share_target.signed_out`; no row applicable →
   `files.share_target.no_options`; unreadable stream → `files.share_target.unsupported`.
4. Web has no share sheet: drag-and-drop + picker are the parity surface.

## 8. Backup (D20)

`BackupExporter.BUSINESS_SCOPED_TABLES += "folders", "files", "folder_access"`;
`collectAttachmentRefs` adds `files` rows (`drive_file_id`, `name`, `mime_type`).
`BackupExporterSchemaGuardTest` will fail until the exporter lists the three new Room
tables — that is the intended guard. `docs/backup-format.md` gains the three tables.

## 9. Tests both implementers must add

- Permission normalization (`manage_folders` inheritance, explicit false) — unit.
- Nav composition (D15 revised): bar = visible modules only, Files last for a
  full-permission owner; Files absent (nothing takes its slot) without `files.view`; no
  viewable module → no bar + Menu start; kebab right of sync opens the Menu — unit
  (Android `NavPermissionsTest`/`NavTabSelectionTest`, web `kebab-menu` +
  `files-permission-gating`).
- Folder-picker "New folder": hidden without `manage_folders`, hidden past the depth cap
  under the selected row, creates + auto-selects, duplicate validation vs the selected
  parent's live siblings — unit (Android `FilesViewModelTest`, web `files-folder-picker`).
- Folder name validation + case-insensitive live duplicate steering — unit/DAO.
- Rename / move (D14, 2026-09-30): file-name rules (1–255, no `/`, duplicates allowed);
  per-row gates hidden-not-greyed per role (viewer / upload-own-only / delete /
  manage_folders) mirroring `files_update`; move validation same-place / cycle / depth
  boundary (9+3 rejected, 7+3 ok) / live duplicate vs tombstone; lazy picker rows
  (roots only, chevrons, ancestors pre-expanded, moved subtree hidden); live error +
  disabled confirm; ONE parent/folder update with the subtree following; best-effort
  Drive rename / re-parent with 403/404 swallowed — unit (Android `FilesTreeMoveTest`,
  `FileActionGatesTest`, `DriveFilesMirrorTest`, `FilesViewModelTest`; web
  `files-rename-move-logic`, `files-rename-move`, `files-drive-client`) + Playwright
  `files-rename-move.spec.ts`.
- Sync spec entries (`folder_access` composite id) — unit.
- Upload pipeline with fake Drive: upload → permission → row push; unlinked → staged
  (Android) / prompt (web); size cap rejects before network — unit.
- Share chooser row visibility per (MIME, count, permissions) — unit (Android).
- Backup schema guard passes with the three tables (Android).
- Web: `__tests__/files-*.test.tsx` for listing/search/breadcrumbs, guest local client
  tables, permission-hidden actions; Playwright smoke for the route + no-access state.

## 10. Deployment order

1. Owner applies `009_files_tab.sql` in the Supabase SQL editor (see
   `~/.luminous/handoff/shared-009-files-owner-ddl.md`), then `010_files_rename_move.sql`
   (idempotent `create or replace` of the two guard functions; until it is applied, a
   move pushed by either client is rejected server-side with the 009 immutability error
   and stays in the outbox as a per-item error — rename of files/folders already works on 009).
2. Owner adds the web origins to the OAuth Web client's Authorized JavaScript origins and
   sets `NEXT_PUBLIC_GOOGLE_WEB_CLIENT_ID` on Vercel (web uploads; the site works without it).
3. Deploy web, release Android (Room 12→13). Reads are tolerant either way: the module is
   hidden until `files.view` is granted, and a missing table only fails the Files screen's
   own queries.
