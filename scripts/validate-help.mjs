#!/usr/bin/env node
// Validates help/guide.json (the single-source user guide) against help/routes.json and the
// merged string catalogs. Pure Node, no dependencies. Exit 1 on any failure.
//
// Checks:
//   1. shape: version, languages (must include en + hi), site.baseUrl, screens[] with
//      id/title/summary/deepLink/tasks[]; tasks with id/title/deepLink/steps[]; steps with
//      en + hi text (optional keys[], platforms[]); optional permission on screen/task
//   2. ids: stable snake_case, unique screen ids, unique task ids within a screen
//   3. en/hi parity: every localized field has a non-empty value in every language; Hindi
//      fields contain Devanagari (a copy-pasted English string is a hard error)
//   4. catalog keys: every `keys` entry exists in the canonical catalog; for keys without
//      ICU placeholders the step text in EACH language must contain that locale's catalog
//      value verbatim (so guide wording cannot drift from the real button labels)
//   5. deepLink: every screen/task deepLink is an id in help/routes.json; platforms[] values
//      are android|web and a task/screen is not restricted to a platform the route lacks
//   6. permission: every permission key is `<section>.<capability>` from
//      permissions/permissions-schema.json
//   7. no PII placeholders / sample data: no phone numbers, emails, ₹ amounts or
//      name-like placeholders ({name}, <customer>) in guide text
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadCatalog, discoverLocales, isNonTranslatable, CANONICAL_LOCALE } from '../codegen/lib.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const GUIDE_PATH = process.env.SAMAROH_GUIDE_PATH || join(ROOT, 'help', 'guide.json');
const ROUTES_PATH = process.env.SAMAROH_ROUTES_PATH || join(ROOT, 'help', 'routes.json');
const PERMS_PATH = join(ROOT, 'permissions', 'permissions-schema.json');

let failures = 0;
const fail = (msg) => {
  console.error(`FAIL: ${msg}`);
  failures += 1;
};

const ID_RE = /^[a-z][a-z0-9_]*$/;
const ROUTE_ID_RE = /^[a-z][a-z0-9_]*(\/[a-z][a-z0-9_]*)*$/;
const PLATFORMS = new Set(['android', 'web']);
const DEVANAGARI_RE = /[\u0900-\u097F]/;
// PII / sample-data patterns that must never appear in guide prose.
const PII_PATTERNS = [
  [/\b(?:\+91[\s-]?)?[6-9]\d{9}\b/, 'Indian phone number'],
  [/\b\d{3}[\s-]\d{3}[\s-]\d{4}\b/, 'phone number'],
  [/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/, 'email address'],
  [/[₹$]\s?\d/, 'currency amount'],
  [/\b\d{1,3}(?:,\d{2,3})+\b/, 'formatted amount'],
  [/\{(name|customer|phone|amount|email|party)\}/i, 'placeholder token'],
  [/<\s*(customer|name|phone|amount|email)\s*>/i, 'angle-bracket placeholder'],
  [/\b(lorem ipsum|john doe|rahul sharma|xxx+)\b/i, 'sample text'],
];

let guide;
let routes;
let perms;
try {
  guide = JSON.parse(readFileSync(GUIDE_PATH, 'utf8'));
} catch (e) {
  fail(`help/guide.json does not parse: ${e.message}`);
  process.exit(1);
}
try {
  routes = JSON.parse(readFileSync(ROUTES_PATH, 'utf8'));
} catch (e) {
  fail(`help/routes.json does not parse: ${e.message}`);
  process.exit(1);
}
try {
  perms = JSON.parse(readFileSync(PERMS_PATH, 'utf8'));
} catch (e) {
  fail(`permissions-schema.json does not parse: ${e.message}`);
  process.exit(1);
}

// ---- routes.json ----
const routeIds = new Set();
if (typeof routes.routes !== 'object' || routes.routes === null) fail('routes.json: missing "routes" object');
for (const [id, target] of Object.entries(routes.routes || {})) {
  if (!ROUTE_ID_RE.test(id)) fail(`routes.json: route id "${id}" must be lowercase segments separated by /`);
  for (const p of PLATFORMS) {
    if (!(p in target)) fail(`routes.json: route "${id}" has no "${p}" entry (use null when absent)`);
    else if (target[p] !== null && typeof target[p] !== 'string') fail(`routes.json: route "${id}".${p} must be a string or null`);
  }
  routeIds.add(id);
}

// ---- permissions ----
const permissionKeys = new Set();
for (const [section, def] of Object.entries(perms.properties || {})) {
  for (const cap of Object.keys(def.properties || {})) permissionKeys.add(`${section}.${cap}`);
}

// ---- catalogs ----
const locales = discoverLocales();
const catalogs = {};
for (const l of locales) catalogs[l] = loadCatalog(l);
const canonical = catalogs[CANONICAL_LOCALE];

// ---- guide shape ----
if (guide.version !== 1) fail(`guide.version must be 1 (got ${JSON.stringify(guide.version)})`);
const langs = Array.isArray(guide.languages) ? guide.languages : [];
if (!langs.includes('en') || !langs.includes('hi')) fail('guide.languages must include "en" and "hi"');
for (const l of langs) if (!locales.includes(l)) fail(`guide language "${l}" has no string catalog`);
if (typeof guide.site?.baseUrl !== 'string' || !/^https:\/\/.+\/$/.test(guide.site.baseUrl)) {
  fail('guide.site.baseUrl must be an https URL ending in /');
}
if (!Array.isArray(guide.screens) || guide.screens.length === 0) {
  fail('guide.screens must be a non-empty array');
  process.exit(1);
}

function checkLocalized(obj, where) {
  if (typeof obj !== 'object' || obj === null) {
    fail(`${where}: must be an object {en, hi}`);
    return;
  }
  for (const l of langs) {
    if (typeof obj[l] !== 'string' || obj[l].trim() === '') fail(`${where}: missing/empty "${l}"`);
  }
  for (const l of Object.keys(obj)) if (!langs.includes(l) && !['keys', 'platforms'].includes(l)) fail(`${where}: unexpected language "${l}"`);
  if (typeof obj.hi === 'string' && obj.hi.trim() !== '' && !DEVANAGARI_RE.test(obj.hi)) {
    fail(`${where}: "hi" contains no Devanagari - looks untranslated: ${JSON.stringify(obj.hi)}`);
  }
}

function checkPii(text, where) {
  for (const [re, label] of PII_PATTERNS) {
    const m = re.exec(text);
    if (m) fail(`${where}: looks like ${label} (${JSON.stringify(m[0])}) - guide text must not contain PII or sample data`);
  }
}

function checkPlatforms(list, where, deepLink) {
  if (list === undefined) return;
  if (!Array.isArray(list) || list.length === 0) {
    fail(`${where}: platforms must be a non-empty array`);
    return;
  }
  for (const p of list) if (!PLATFORMS.has(p)) fail(`${where}: unknown platform "${p}"`);
  if (deepLink && routes.routes[deepLink]) {
    for (const p of list) {
      if (PLATFORMS.has(p) && routes.routes[deepLink][p] === null) {
        fail(`${where}: restricted to "${p}" but route "${deepLink}" has no ${p} target`);
      }
    }
  }
}

function checkDeepLink(id, where) {
  if (typeof id !== 'string' || !routeIds.has(id)) fail(`${where}: deepLink ${JSON.stringify(id)} is not an id in help/routes.json`);
}

function checkPermission(key, where) {
  if (key === undefined) return;
  if (!permissionKeys.has(key)) fail(`${where}: permission "${key}" is not <section>.<capability> in permissions-schema.json`);
}

function checkStepKeys(step, where) {
  if (step.keys === undefined) return;
  if (!Array.isArray(step.keys) || step.keys.length === 0) {
    fail(`${where}: keys must be a non-empty array`);
    return;
  }
  for (const k of step.keys) {
    if (!(k in canonical)) {
      fail(`${where}: catalog key "${k}" does not exist`);
      continue;
    }
    if (isNonTranslatable(canonical[k])) {
      fail(`${where}: key "${k}" is non-translatable data, not a UI label`);
      continue;
    }
    for (const l of langs) {
      const value = catalogs[l][k]?.value;
      if (typeof value !== 'string') continue; // parity is the catalog validator's job
      if (/[{}]/.test(value)) continue; // placeholders/plurals: cannot be matched verbatim
      if (typeof step[l] === 'string' && !step[l].includes(value)) {
        fail(`${where} [${l}]: step text must contain the exact label for ${k}: ${JSON.stringify(value)}`);
      }
    }
  }
}

const screenIds = new Set();
let taskCount = 0;
let stepCount = 0;
guide.screens.forEach((screen, si) => {
  const where = `screens[${si}]${screen.id ? ` (${screen.id})` : ''}`;
  if (typeof screen.id !== 'string' || !ID_RE.test(screen.id)) fail(`${where}: id must be snake_case`);
  else if (screenIds.has(screen.id)) fail(`${where}: duplicate screen id`);
  else screenIds.add(screen.id);
  checkLocalized(screen.title, `${where}.title`);
  checkLocalized(screen.summary, `${where}.summary`);
  checkDeepLink(screen.deepLink, where);
  checkPlatforms(screen.platforms, where, screen.deepLink);
  checkPermission(screen.permission, where);
  for (const l of langs) {
    checkPii(screen.title?.[l] ?? '', `${where}.title.${l}`);
    checkPii(screen.summary?.[l] ?? '', `${where}.summary.${l}`);
  }
  if (!Array.isArray(screen.tasks) || screen.tasks.length === 0) {
    fail(`${where}: tasks must be a non-empty array`);
    return;
  }
  const taskIds = new Set();
  screen.tasks.forEach((task, ti) => {
    const twhere = `${where}.tasks[${ti}]${task.id ? ` (${task.id})` : ''}`;
    taskCount += 1;
    if (typeof task.id !== 'string' || !ID_RE.test(task.id)) fail(`${twhere}: id must be snake_case`);
    else if (taskIds.has(task.id)) fail(`${twhere}: duplicate task id in screen`);
    else taskIds.add(task.id);
    checkLocalized(task.title, `${twhere}.title`);
    checkDeepLink(task.deepLink, twhere);
    checkPlatforms(task.platforms, twhere, task.deepLink);
    checkPermission(task.permission, twhere);
    for (const l of langs) checkPii(task.title?.[l] ?? '', `${twhere}.title.${l}`);
    if (!Array.isArray(task.steps) || task.steps.length === 0) {
      fail(`${twhere}: steps must be a non-empty array`);
      return;
    }
    task.steps.forEach((step, sti) => {
      const swhere = `${twhere}.steps[${sti}]`;
      stepCount += 1;
      checkLocalized(step, swhere);
      checkPlatforms(step.platforms, swhere, task.deepLink);
      checkStepKeys(step, swhere);
      for (const l of langs) checkPii(step[l] ?? '', `${swhere}.${l}`);
      // A step restricted to a subset of platforms must leave the task coverable on each
      // platform the task targets: every platform needs at least one applicable step.
    });
    const taskPlatforms = task.platforms || screen.platforms || [...PLATFORMS];
    for (const p of taskPlatforms) {
      const applicable = task.steps.some((s) => !s.platforms || s.platforms.includes(p));
      if (!applicable) fail(`${twhere}: no step applies to platform "${p}"`);
    }
  });
});

if (failures) {
  console.error(`\nHelp guide validation FAILED with ${failures} error(s).`);
  process.exit(1);
}
console.log(
  `Help guide OK: ${guide.screens.length} screens, ${taskCount} tasks, ${stepCount} steps × ${langs.length} languages (${langs.join(', ')}); ${routeIds.size} routes.`,
);
