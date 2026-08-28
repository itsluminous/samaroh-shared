#!/usr/bin/env node
// cleanup-storage.mjs — empties the data-dependent Supabase Storage buckets.
//
// Companion to cleanup-data.sql. Hosted Supabase forbids SQL against the
// storage tables (ERROR 42501: "Direct deletion from storage tables is not
// allowed. Use the Storage API instead."), so files are wiped here via the
// Storage API.
//
// What it does:
//   - Empties 'inventory-images' (item photos) and 'booking-invoices'
//     (generated invoice PDFs): recursively lists every object (storage
//     list() is folder-scoped, so prefixes are walked), then removes them
//     in batches.
//   - KEEPS the 'logos' bucket untouched — business logos are setup, not data.
//   - Idempotent: already-empty buckets report 0 files and succeed.
//
// Credentials — READ FROM ENV AT RUN TIME, never stored in a file:
//   SUPABASE_SERVICE_KEY   (required — service role key; anon cannot list
//                           these private buckets)
//   SUPABASE_URL           (optional; defaults to the Samaroh project URL)
//
// Setup (once):  cd scripts && npm i        # installs @supabase/supabase-js
//
// Usage:
//   node cleanup-storage.mjs --dry-run      # list + count only, deletes nothing
//   SUPABASE_SERVICE_KEY=<key> node cleanup-storage.mjs
//   (--dry-run also needs the key: listing private buckets requires it.)

const DRY_RUN = process.argv.includes('--dry-run') || process.env.DRY_RUN === '1';
const SUPABASE_URL =
  process.env.SUPABASE_URL || 'https://xhcxkmlxlryvjxswwiqp.supabase.co';
const SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY || '';

export const BUCKETS_TO_EMPTY = ['inventory-images', 'booking-invoices'];
export const BUCKETS_KEPT = ['logos'];
const PAGE = 1000; // list() page size
const REMOVE_BATCH = 100; // paths per remove() call

function fail(msg) {
  console.error(`✖ ${msg}`);
  process.exit(1);
}

/**
 * Recursively collect every object path in a bucket. Supabase storage list()
 * is folder-scoped: it returns the entries directly under one prefix, with
 * folders distinguished by id === null — so we walk each folder prefix.
 */
export async function listAllObjects(storage, bucket, prefix = '') {
  const paths = [];
  for (let offset = 0; ; offset += PAGE) {
    const { data, error } = await storage.from(bucket).list(prefix, {
      limit: PAGE,
      offset,
      sortBy: { column: 'name', order: 'asc' },
    });
    if (error) throw new Error(`list ${bucket}/${prefix}: ${error.message}`);
    if (!data || data.length === 0) break;
    for (const entry of data) {
      const full = prefix ? `${prefix}/${entry.name}` : entry.name;
      if (entry.id === null) {
        // folder — recurse into it
        paths.push(...(await listAllObjects(storage, bucket, full)));
      } else {
        paths.push(full);
      }
    }
    if (data.length < PAGE) break;
  }
  return paths;
}

/** Empty one bucket (or just report, when dryRun). Returns the file count. */
export async function emptyBucket(storage, bucket, { dryRun = false, log = console.log } = {}) {
  const paths = await listAllObjects(storage, bucket);
  if (paths.length === 0) {
    log(`  ${bucket}: already empty (0 files)`);
    return 0;
  }
  if (dryRun) {
    for (const p of paths) log(`  would delete ${bucket}/${p}`);
    log(`  ${bucket}: ${paths.length} file(s) would be deleted`);
    return paths.length;
  }
  let removed = 0;
  for (let i = 0; i < paths.length; i += REMOVE_BATCH) {
    const batch = paths.slice(i, i + REMOVE_BATCH);
    const { error } = await storage.from(bucket).remove(batch);
    if (error) throw new Error(`remove ${bucket} batch @${i}: ${error.message}`);
    removed += batch.length;
  }
  log(`  ${bucket}: ${removed} file(s) deleted`);
  return removed;
}

async function main() {
  if (!SERVICE_KEY) {
    fail(
      'SUPABASE_SERVICE_KEY not set. Paste the service role key into the env for this run only:\n' +
        '  SUPABASE_SERVICE_KEY=<key> node cleanup-storage.mjs --dry-run   # preview\n' +
        '  SUPABASE_SERVICE_KEY=<key> node cleanup-storage.mjs             # delete\n' +
        '(The key is required even for --dry-run: listing private buckets needs it.\n' +
        ' Find it in Supabase dashboard -> Project Settings -> API -> service_role.)'
    );
  }

  // Imported lazily so the usage message above works before `npm i`.
  const { createClient } = await import('@supabase/supabase-js');
  const db = createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  console.log(
    `${DRY_RUN ? 'DRY RUN — deleting nothing. ' : ''}Emptying: ${BUCKETS_TO_EMPTY.join(', ')}. ` +
      `Keeping: ${BUCKETS_KEPT.join(', ')}.`
  );

  const counts = {};
  for (const bucket of BUCKETS_TO_EMPTY) {
    counts[bucket] = await emptyBucket(db.storage, bucket, { dryRun: DRY_RUN });
  }

  const total = Object.values(counts).reduce((a, b) => a + b, 0);
  console.log(
    `\nDONE — ${total} file(s) ${DRY_RUN ? 'would be' : ''} deleted ` +
      `(${BUCKETS_TO_EMPTY.map((b) => `${b}: ${counts[b]}`).join(', ')}). ` +
      `'${BUCKETS_KEPT.join("', '")}' kept.`
  );
}

// Run only when executed directly (keeps the helpers importable for tests).
if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((e) => fail(e.stack || e.message));
}
