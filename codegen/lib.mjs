// Shared helpers for the string-catalog code generators. Pure Node, no dependencies.
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

export const STRINGS_DIR = join(dirname(fileURLToPath(import.meta.url)), '..', 'strings');
export const CANONICAL_LOCALE = 'en';

/** Discover locales from strings/catalog.<locale>.json files. */
export function discoverLocales() {
  return readdirSync(STRINGS_DIR)
    .map((f) => /^catalog\.([a-z]{2}(?:-[A-Za-z]+)?)\.json$/.exec(f))
    .filter(Boolean)
    .map((m) => m[1])
    .sort((a, b) => (a === CANONICAL_LOCALE ? -1 : b === CANONICAL_LOCALE ? 1 : a.localeCompare(b)));
}

/** Load one catalog file and validate its basic shape. */
export function loadCatalog(locale) {
  const file = join(STRINGS_DIR, `catalog.${locale}.json`);
  const data = JSON.parse(readFileSync(file, 'utf8'));
  for (const [key, entry] of Object.entries(data)) {
    if (typeof entry !== 'object' || entry === null || typeof entry.value !== 'string') {
      throw new Error(`${file}: entry "${key}" must be an object with a string "value"`);
    }
  }
  return data;
}

/**
 * Assert exact key parity between the canonical locale and every other locale.
 * Exits the process with code 1 on any mismatch.
 */
export function assertKeyParity(catalogs) {
  const locales = Object.keys(catalogs);
  const canonicalKeys = new Set(Object.keys(catalogs[CANONICAL_LOCALE]));
  let ok = true;
  for (const locale of locales) {
    if (locale === CANONICAL_LOCALE) continue;
    const keys = new Set(Object.keys(catalogs[locale]));
    for (const k of canonicalKeys) {
      if (!keys.has(k)) {
        console.error(`PARITY ERROR: key "${k}" present in ${CANONICAL_LOCALE} but missing in ${locale}`);
        ok = false;
      }
    }
    for (const k of keys) {
      if (!canonicalKeys.has(k)) {
        console.error(`PARITY ERROR: key "${k}" present in ${locale} but missing in ${CANONICAL_LOCALE}`);
        ok = false;
      }
    }
  }
  if (!ok) {
    console.error('Catalog key parity check FAILED.');
    process.exit(1);
  }
}

/**
 * Parse an ICU plural value of the shape "{arg, plural, one {...} other {...}}".
 * Returns { arg, forms: { one: "...", other: "..." } } or null if the value is
 * not a whole-string plural message.
 */
export function parseIcuPlural(value) {
  const m = /^\s*\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*,\s*plural\s*,\s*(.*)\}\s*$/s.exec(value);
  if (!m) return null;
  const arg = m[1];
  const body = m[2];
  const forms = {};
  const re = /(zero|one|two|few|many|other|=\d+)\s*\{/g;
  let match;
  while ((match = re.exec(body)) !== null) {
    // Find the matching closing brace for this form, honoring nesting.
    let depth = 1;
    let i = re.lastIndex;
    while (i < body.length && depth > 0) {
      if (body[i] === '{') depth += 1;
      else if (body[i] === '}') depth -= 1;
      i += 1;
    }
    forms[match[1]] = body.slice(re.lastIndex, i - 1);
    re.lastIndex = i;
  }
  if (!forms.other) return null; // ICU requires "other"; treat as plain string otherwise
  return { arg, forms };
}

/** Extract named ICU placeholder names ({name}) from a simple (non-plural) value, in order. */
export function extractPlaceholders(value) {
  const names = [];
  const re = /\{([A-Za-z_][A-Za-z0-9_]*)\}/g;
  let m;
  while ((m = re.exec(value)) !== null) {
    if (!names.includes(m[1])) names.push(m[1]);
  }
  return names;
}
