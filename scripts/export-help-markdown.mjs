#!/usr/bin/env node
// Exports help/guide.json to one Markdown file per language: help/guide.<lang>.md.
// Pure Node, no dependencies. These files are the Gemini Gem "knowledge" upload
// (help/gemini/gem-instructions.md) and a human-readable mirror of the guide.
//
//   node scripts/export-help-markdown.mjs            # writes help/guide.en.md + help/guide.hi.md
//   node scripts/export-help-markdown.mjs --check    # exit 1 if the committed files are stale
//   node scripts/export-help-markdown.mjs --out DIR  # write elsewhere (used by the Pages build)
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const GUIDE_PATH = process.env.SAMAROH_GUIDE_PATH || join(ROOT, 'help', 'guide.json');

const args = process.argv.slice(2);
const check = args.includes('--check');
const outIdx = args.indexOf('--out');
const OUT_DIR = outIdx >= 0 ? args[outIdx + 1] : join(ROOT, 'help');

const guide = JSON.parse(readFileSync(GUIDE_PATH, 'utf8'));

const UI = {
  en: {
    title: 'Samaroh - User guide',
    intro:
      'How to do everyday tasks in the Samaroh app (Android and web). Button names are written exactly as they appear in the app. Generated from help/guide.json - do not edit by hand.',
    contents: 'Contents',
    tasks: 'Tasks',
    permission: 'Needs permission',
    platformOnly: { android: 'Phone app only', web: 'Web only' },
    stepPlatform: { android: 'phone', web: 'web' },
    online: 'Online version',
  },
  hi: {
    title: 'समारोह - उपयोग गाइड',
    intro:
      'समारोह ऐप (Android और वेब) में रोज़ के काम कैसे करें। बटनों के नाम ठीक वैसे ही लिखे हैं जैसे ऐप में दिखते हैं। help/guide.json से बनाया गया - हाथ से न बदलें।',
    contents: 'विषय-सूची',
    tasks: 'काम',
    permission: 'अनुमति चाहिए',
    platformOnly: { android: 'सिर्फ़ फ़ोन ऐप में', web: 'सिर्फ़ वेब पर' },
    stepPlatform: { android: 'फ़ोन', web: 'वेब' },
    online: 'ऑनलाइन संस्करण',
  },
};

export function pageUrl(lang, screenId) {
  return guide.site.pagePattern
    .replace('{baseUrl}', guide.site.baseUrl)
    .replace('{lang}', lang)
    .replace('{screenId}', screenId);
}

export function indexUrl(lang) {
  return guide.site.indexPattern.replace('{baseUrl}', guide.site.baseUrl).replace('{lang}', lang);
}

function platformOnly(list, lang) {
  if (!list || list.length !== 1) return '';
  return ` *(${UI[lang].platformOnly[list[0]]})*`;
}

export function renderMarkdown(lang) {
  const ui = UI[lang] || UI.en;
  const lines = [];
  lines.push(`# ${ui.title}`, '', ui.intro, '', `${ui.online}: ${indexUrl(lang)}`, '', `## ${ui.contents}`, '');
  for (const s of guide.screens) lines.push(`- [${s.title[lang]}](#${s.id})`);
  lines.push('');
  for (const s of guide.screens) {
    lines.push(`<a id="${s.id}"></a>`, '', `## ${s.title[lang]}${platformOnly(s.platforms, lang)}`, '', s.summary[lang], '');
    lines.push(`${ui.online}: ${pageUrl(lang, s.id)}`, '');
    for (const t of s.tasks) {
      lines.push(`### ${t.title[lang]}${platformOnly(t.platforms, lang)}`, '');
      if (t.permission) lines.push(`*${ui.permission}: \`${t.permission}\`*`, '');
      let n = 0;
      for (const step of t.steps) {
        n += 1;
        const tag = step.platforms && step.platforms.length === 1 ? ` *(${ui.stepPlatform[step.platforms[0]]})*` : '';
        lines.push(`${n}. ${step[lang]}${tag}`);
      }
      lines.push('');
    }
  }
  return `${lines.join('\n').trimEnd()}\n`;
}

const isMain = process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
if (isMain) {
  let stale = 0;
  for (const lang of guide.languages) {
    const md = renderMarkdown(lang);
    const target = join(OUT_DIR, `guide.${lang}.md`);
    if (check) {
      const current = existsSync(target) ? readFileSync(target, 'utf8') : '';
      if (current !== md) {
        console.error(`STALE: ${target} differs from guide.json - run node scripts/export-help-markdown.mjs`);
        stale += 1;
      }
    } else {
      mkdirSync(dirname(target), { recursive: true });
      writeFileSync(target, md);
      console.log(`wrote ${target}`);
    }
  }
  if (stale) process.exit(1);
  if (check) console.log('Help markdown exports are up to date.');
}
