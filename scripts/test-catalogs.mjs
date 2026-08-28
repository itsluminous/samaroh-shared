#!/usr/bin/env node
// Fixture-driven tests for the catalog validator + code generators, focused on the
// non-translatable ("translatable": false) entry contract:
//   - an en-only non-translatable key passes validation (exempt from key parity)
//   - a translated-locale entry for a non-translatable key is a hard error
//   - translatable may only be false (or omitted); any other value is a hard error
//   - a non-translatable plural is a hard error
//   - ordinary key parity is still enforced (regression)
//   - gen-android emits translatable="false" in values/ only (plus formatted="false"
//     when the value carries a literal %); the key is absent from values-<locale>/
//   - gen-web copies the en value into every locale's messages file
// Pure Node, no dependencies. Runs each tool as a subprocess against a temp fixture
// catalog via the SAMAROH_STRINGS_DIR override. Exit 1 on any failure.
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

let failures = 0;
const check = (ok, label, detail = '') => {
  if (ok) {
    console.log(`ok   ${label}`);
  } else {
    console.error(`FAIL ${label}${detail ? `\n     ${detail}` : ''}`);
    failures += 1;
  }
};

/** Write a fixture catalog dir: { en: {...}, hi: {...} } key → entry object. */
function fixture(catalogs) {
  const dir = mkdtempSync(join(tmpdir(), 'samaroh-strings-'));
  mkdirSync(join(dir, 'fragments'));
  for (const [locale, entries] of Object.entries(catalogs)) {
    writeFileSync(join(dir, `catalog.${locale}.json`), JSON.stringify(entries, null, 2));
  }
  return dir;
}

/** Run a repo script with SAMAROH_STRINGS_DIR pointed at the fixture. */
function run(script, stringsDir, args = []) {
  return spawnSync('node', [join(ROOT, script), ...args], {
    env: { ...process.env, SAMAROH_STRINGS_DIR: stringsDir },
    encoding: 'utf8',
    timeout: 30_000,
  });
}

const entry = (value, extra = {}) => ({ value, description: 'test entry', ...extra });

// A well-formed catalog: one ordinary key in both locales, one en-only non-translatable.
const GOOD = {
  en: {
    'menu.about.title': entry('About'),
    'menu.about.donate_uri': entry('upi://pay?pa=someone@bank&cn=App&tn=App%20donation', { translatable: false }),
  },
  hi: {
    'menu.about.title': entry('परिचय'),
  },
};

// --- validator ---------------------------------------------------------------------

{
  const dir = fixture(GOOD);
  const r = run('scripts/validate-catalogs.mjs', dir);
  check(r.status === 0, 'validator accepts an en-only non-translatable key', r.stderr);
  rmSync(dir, { recursive: true, force: true });
}

{
  const dir = fixture({
    en: GOOD.en,
    hi: { ...GOOD.hi, 'menu.about.donate_uri': entry('upi://anything') },
  });
  const r = run('scripts/validate-catalogs.mjs', dir);
  check(
    r.status !== 0 && r.stderr.includes('non-translatable'),
    'validator rejects a hi entry for a non-translatable key',
    r.stderr,
  );
  rmSync(dir, { recursive: true, force: true });
}

{
  const dir = fixture({
    en: { 'menu.about.title': entry('About', { translatable: true }) },
    hi: { 'menu.about.title': entry('परिचय') },
  });
  const r = run('scripts/validate-catalogs.mjs', dir);
  check(
    r.status !== 0 && r.stderr.includes('translatable'),
    'validator rejects translatable values other than false',
    r.stderr,
  );
  rmSync(dir, { recursive: true, force: true });
}

{
  const dir = fixture({
    en: { 'menu.about.count': entry('{count, plural, one {# item} other {# items}}', { translatable: false }) },
    hi: {},
  });
  const r = run('scripts/validate-catalogs.mjs', dir);
  check(
    r.status !== 0 && r.stderr.includes('plural'),
    'validator rejects a non-translatable plural',
    r.stderr,
  );
  rmSync(dir, { recursive: true, force: true });
}

{
  const dir = fixture({ en: { 'menu.about.title': entry('About') }, hi: {} });
  const r = run('scripts/validate-catalogs.mjs', dir);
  check(
    r.status !== 0 && r.stderr.includes('missing in hi'),
    'validator still rejects an ordinary key missing in hi (regression)',
    r.stderr,
  );
  rmSync(dir, { recursive: true, force: true });
}

// --- gen-android -------------------------------------------------------------------

{
  const dir = fixture(GOOD);
  const out = mkdtempSync(join(tmpdir(), 'samaroh-res-'));
  const r = run('codegen/gen-android.mjs', dir, [out]);
  check(r.status === 0, 'gen-android succeeds with a non-translatable key', r.stderr);
  if (r.status === 0) {
    const values = readFileSync(join(out, 'values', 'strings.xml'), 'utf8');
    const valuesHi = readFileSync(join(out, 'values-hi', 'strings.xml'), 'utf8');
    check(
      values.includes('<string name="menu_about_donate_uri" translatable="false" formatted="false">'),
      'gen-android emits translatable="false" (+ formatted="false" for a % value) in values/',
      values,
    );
    check(
      values.includes('upi://pay?pa=someone@bank&amp;cn=App&amp;tn=App%20donation'),
      'gen-android escapes the non-translatable value verbatim',
      values,
    );
    check(!valuesHi.includes('menu_about_donate_uri'), 'gen-android omits the key from values-hi/', valuesHi);
    check(valuesHi.includes('menu_about_title'), 'gen-android still localizes ordinary keys', valuesHi);
  }
  rmSync(dir, { recursive: true, force: true });
  rmSync(out, { recursive: true, force: true });
}

// --- gen-web -----------------------------------------------------------------------

{
  const dir = fixture(GOOD);
  const out = mkdtempSync(join(tmpdir(), 'samaroh-msg-'));
  const r = run('codegen/gen-web.mjs', dir, [out]);
  check(r.status === 0, 'gen-web succeeds with a non-translatable key', r.stderr);
  if (r.status === 0) {
    const en = JSON.parse(readFileSync(join(out, 'en.json'), 'utf8'));
    const hi = JSON.parse(readFileSync(join(out, 'hi.json'), 'utf8'));
    check(
      hi.menu.about.donate_uri === en.menu.about.donate_uri &&
        en.menu.about.donate_uri === GOOD.en['menu.about.donate_uri'].value,
      'gen-web carries the en value of a non-translatable key into every locale',
      JSON.stringify({ en: en.menu.about, hi: hi.menu.about }),
    );
    check(hi.menu.about.title === 'परिचय', 'gen-web still localizes ordinary keys');
  }
  rmSync(dir, { recursive: true, force: true });
  rmSync(out, { recursive: true, force: true });
}

if (failures) {
  console.error(`\nCatalog pipeline tests FAILED: ${failures} failing check(s).`);
  process.exit(1);
}
console.log('\nCatalog pipeline tests OK.');
