// Shared helpers for the string-catalog code generators. Pure Node, no dependencies.
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

// SAMAROH_STRINGS_DIR lets the validator/codegen test suite point at fixture catalogs.
export const STRINGS_DIR =
  process.env.SAMAROH_STRINGS_DIR || join(dirname(fileURLToPath(import.meta.url)), '..', 'strings');
export const FRAGMENTS_DIR = join(STRINGS_DIR, 'fragments');
export const CANONICAL_LOCALE = 'en';

/**
 * Non-translatable entries (`"translatable": false`) carry data-like values — URIs,
 * technical identifiers — that must never be localized. They live ONLY in the canonical
 * (en) catalog: key parity deliberately excludes them, and a translated-locale entry for
 * such a key is a HARD ERROR (a silently-ignored translation would drift from the
 * canonical value). Android codegen emits them with `translatable="false"` in the default
 * values/ resources only; web codegen copies the en value into every locale.
 */
export const isNonTranslatable = (entry) => entry.translatable === false;

const LOCALE_PATTERN = '[a-z]{2}(?:-[A-Za-z]+)?';
const FRAGMENT_FILE_RE = new RegExp(`^([a-z][a-z0-9_-]*)\\.(${LOCALE_PATTERN})\\.json$`);

/** List strings/fragments/ entries, tolerating a missing directory. Dotfiles (.gitkeep) are ignored. */
function fragmentDirEntries() {
  if (!existsSync(FRAGMENTS_DIR)) return [];
  return readdirSync(FRAGMENTS_DIR).filter((f) => !f.startsWith('.'));
}

/**
 * Discover locales from strings/catalog.<locale>.json files, and validate that every
 * fragment file (strings/fragments/<namespace>.<locale>.json) is well-formed and uses a
 * locale that has a base catalog. Throws on a malformed fragment filename or an unknown
 * fragment locale — both would otherwise be silently skipped.
 */
export function discoverLocales() {
  const locales = readdirSync(STRINGS_DIR)
    .map((f) => new RegExp(`^catalog\\.(${LOCALE_PATTERN})\\.json$`).exec(f))
    .filter(Boolean)
    .map((m) => m[1])
    .sort((a, b) => (a === CANONICAL_LOCALE ? -1 : b === CANONICAL_LOCALE ? 1 : a.localeCompare(b)));
  for (const f of fragmentDirEntries()) {
    const m = FRAGMENT_FILE_RE.exec(f);
    if (!m) {
      throw new Error(
        `fragments/${f}: does not match <namespace>.<locale>.json (namespace: lowercase [a-z0-9_-])`,
      );
    }
    if (!locales.includes(m[2])) {
      throw new Error(
        `fragments/${f}: locale "${m[2]}" has no base catalog.${m[2]}.json — fragment would be silently ignored`,
      );
    }
  }
  return locales;
}

/** All catalog source files for a locale: the base catalog plus fragments, sorted by namespace. */
export function catalogFilesFor(locale) {
  const files = [join(STRINGS_DIR, `catalog.${locale}.json`)];
  const fragments = fragmentDirEntries()
    .filter((f) => {
      const m = FRAGMENT_FILE_RE.exec(f);
      return m && m[2] === locale;
    })
    .sort()
    .map((f) => join(FRAGMENTS_DIR, f));
  return files.concat(fragments);
}

/**
 * Load the merged catalog for a locale: strings/catalog.<locale>.json plus every
 * strings/fragments/*.<locale>.json. Validates each entry's basic shape. A key appearing
 * in more than one file (for the same locale) is a HARD ERROR — namespaces are owned by
 * exactly one file.
 */
export function loadCatalog(locale) {
  const merged = {};
  const keySource = {};
  for (const file of catalogFilesFor(locale)) {
    const data = JSON.parse(readFileSync(file, 'utf8'));
    for (const [key, entry] of Object.entries(data)) {
      if (typeof entry !== 'object' || entry === null || typeof entry.value !== 'string') {
        throw new Error(`${file}: entry "${key}" must be an object with a string "value"`);
      }
      if ('translatable' in entry && entry.translatable !== false) {
        throw new Error(
          `${file}: entry "${key}" has translatable=${JSON.stringify(entry.translatable)} — only false (or omitting the field) is allowed`,
        );
      }
      if (key in merged) {
        throw new Error(
          `DUPLICATE KEY: "${key}" defined in both ${keySource[key]} and ${file} (locale ${locale})`,
        );
      }
      merged[key] = entry;
      keySource[key] = file;
    }
  }
  return merged;
}

/**
 * Assert exact key parity between the canonical locale and every other locale.
 * Non-translatable keys (see [isNonTranslatable]) are canonical-only: they are exempt
 * from the missing-in-locale check, and their PRESENCE in a translated locale is an
 * error. Exits the process with code 1 on any mismatch.
 */
export function assertKeyParity(catalogs) {
  const locales = Object.keys(catalogs);
  const canonical = catalogs[CANONICAL_LOCALE];
  const canonicalKeys = new Set(Object.keys(canonical));
  let ok = true;
  for (const locale of locales) {
    if (locale === CANONICAL_LOCALE) continue;
    const keys = new Set(Object.keys(catalogs[locale]));
    for (const k of canonicalKeys) {
      if (isNonTranslatable(canonical[k])) {
        if (keys.has(k)) {
          console.error(`PARITY ERROR: key "${k}" is non-translatable (en-only) but has an entry in ${locale} — delete it`);
          ok = false;
        }
        continue;
      }
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
