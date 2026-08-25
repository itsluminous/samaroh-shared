#!/usr/bin/env node
// Generates next-intl message files from the canonical catalog.
//   node gen-web.mjs <output-messages-dir>
// Emits <output-messages-dir>/<locale>.json with keys nested by dot segments
// (e.g. "common.action.save" -> { common: { action: { save: "…" } } }).
// ICU values pass through unchanged — next-intl consumes ICU natively.
// Pure Node, no dependencies. Exits non-zero on key-parity mismatch.
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { assertKeyParity, discoverLocales, loadCatalog } from './lib.mjs';

const outDir = process.argv[2];
if (!outDir) {
  console.error('Usage: node gen-web.mjs <output-messages-dir>');
  process.exit(1);
}

const locales = discoverLocales();
const catalogs = Object.fromEntries(locales.map((l) => [l, loadCatalog(l)]));
assertKeyParity(catalogs);

mkdirSync(outDir, { recursive: true });

for (const locale of locales) {
  const nested = {};
  for (const [key, entry] of Object.entries(catalogs[locale])) {
    const segments = key.split('.');
    let node = nested;
    for (const seg of segments.slice(0, -1)) {
      if (typeof node[seg] === 'string') {
        console.error(`ERROR: key "${key}" collides with a shorter key ending at segment "${seg}"`);
        process.exit(1);
      }
      node = node[seg] ??= {};
    }
    const leaf = segments.at(-1);
    if (leaf in node) {
      console.error(`ERROR: key "${key}" collides with an existing longer key at its leaf segment`);
      process.exit(1);
    }
    node[leaf] = entry.value;
  }
  const file = join(outDir, `${locale}.json`);
  writeFileSync(file, `${JSON.stringify(nested, null, 2)}\n`, 'utf8');
  console.log(`wrote ${file} (${Object.keys(catalogs[locale]).length} keys)`);
}
