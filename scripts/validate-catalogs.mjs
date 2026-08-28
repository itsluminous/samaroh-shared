#!/usr/bin/env node
// Validates the string catalogs. Pure Node, no dependencies. Exit 1 on any failure.
// Sources per locale: strings/catalog.<locale>.json merged with every
// strings/fragments/*.<locale>.json — a key defined in more than one file is a hard error.
// Checks:
//   1. every catalog/fragment parses; every entry is {value: string, description: string};
//      no duplicate keys across the base catalog and fragment files of a locale
//   2. key naming convention: module.screen.element (lowercase snake_case dot segments)
//   3. exact key parity across all locales (over the merged set). Entries marked
//      "translatable": false are canonical(en)-only: they are exempt from parity, and a
//      translated-locale entry for such a key is a hard ERROR (a silently-ignored
//      translation would drift from the canonical value)
//   4. ICU placeholder-name parity per key across locales
//   5. plural shape parity (a key that is a plural in en must be a plural everywhere);
//      a non-translatable entry must not be a plural (nothing locale-varying to pluralize)
import {
  CANONICAL_LOCALE,
  discoverLocales,
  extractPlaceholders,
  isNonTranslatable,
  loadCatalog,
  parseIcuPlural,
} from '../codegen/lib.mjs';

const KEY_RE = /^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$/;

let failures = 0;
const fail = (msg) => {
  console.error(`FAIL: ${msg}`);
  failures += 1;
};

let locales;
try {
  locales = discoverLocales();
} catch (e) {
  fail(e.message);
  process.exit(1);
}
if (!locales.includes(CANONICAL_LOCALE)) {
  fail(`canonical locale "${CANONICAL_LOCALE}" catalog not found`);
  process.exit(1);
}

const catalogs = {};
for (const locale of locales) {
  try {
    catalogs[locale] = loadCatalog(locale);
  } catch (e) {
    fail(`[${locale}] ${e.message}`);
  }
}
if (failures) process.exit(1);

// 1 + 2: shape and key naming
for (const locale of locales) {
  for (const [key, entry] of Object.entries(catalogs[locale])) {
    if (!KEY_RE.test(key)) fail(`[${locale}] key "${key}" violates module.screen.element naming`);
    if (typeof entry.description !== 'string' || entry.description.trim() === '') {
      fail(`[${locale}] key "${key}" is missing a description`);
    }
    if (entry.value.trim() === '') fail(`[${locale}] key "${key}" has an empty value`);
    if (isNonTranslatable(entry) && parseIcuPlural(entry.value)) {
      fail(`[${locale}] key "${key}" is non-translatable but a plural — plurals are inherently locale-varying`);
    }
  }
}

// 3: key parity (non-translatable keys are en-only; a hi/… entry for one is an error)
const canonicalKeys = new Set(Object.keys(catalogs[CANONICAL_LOCALE]));
for (const locale of locales) {
  if (locale === CANONICAL_LOCALE) continue;
  const keys = new Set(Object.keys(catalogs[locale]));
  for (const k of canonicalKeys) {
    if (isNonTranslatable(catalogs[CANONICAL_LOCALE][k])) {
      if (keys.has(k)) fail(`key "${k}" is non-translatable (en-only) but has an entry in ${locale} — delete it`);
      continue;
    }
    if (!keys.has(k)) fail(`key "${k}" missing in ${locale}`);
  }
  for (const k of keys) if (!canonicalKeys.has(k)) fail(`key "${k}" in ${locale} does not exist in ${CANONICAL_LOCALE}`);
}

// 4 + 5: placeholder and plural parity
for (const key of canonicalKeys) {
  const enValue = catalogs[CANONICAL_LOCALE][key].value;
  const enPlural = parseIcuPlural(enValue);
  for (const locale of locales) {
    if (locale === CANONICAL_LOCALE || !(key in catalogs[locale])) continue;
    const value = catalogs[locale][key].value;
    const plural = parseIcuPlural(value);
    if (Boolean(enPlural) !== Boolean(plural)) {
      fail(`key "${key}": plural in ${enPlural ? CANONICAL_LOCALE : locale} but not in ${plural ? CANONICAL_LOCALE : locale}`);
      continue;
    }
    if (enPlural) {
      if (enPlural.arg !== plural.arg) {
        fail(`key "${key}": plural argument "${plural.arg}" in ${locale} differs from "${enPlural.arg}" in ${CANONICAL_LOCALE}`);
      }
      if (!('other' in plural.forms)) fail(`key "${key}" [${locale}]: plural missing required "other" category`);
    } else {
      const enPh = [...extractPlaceholders(enValue)].sort();
      const ph = [...extractPlaceholders(value)].sort();
      if (JSON.stringify(enPh) !== JSON.stringify(ph)) {
        fail(`key "${key}": placeholders {${ph}} in ${locale} differ from {${enPh}} in ${CANONICAL_LOCALE}`);
      }
    }
  }
}

if (failures) {
  console.error(`\nCatalog validation FAILED with ${failures} error(s).`);
  process.exit(1);
}
console.log(`Catalog validation OK: ${canonicalKeys.size} keys × ${locales.length} locales (${locales.join(', ')}).`);
