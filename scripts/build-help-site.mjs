#!/usr/bin/env node
// Builds the public static help site from help/guide.json. Pure Node, no dependencies.
//
//   node scripts/build-help-site.mjs [--out DIR]     (default: build/help-site)
//
// Output layout (served by GitHub Pages at guide.site.baseUrl, see help/README.md):
//   index.html                    → redirects to hi/index.html (owner's default language)
//   help/index.html               → same redirect
//   help/<lang>/index.html        → list of screens
//   help/<lang>/<screenId>.html   → one page per screen (stable URL; Android AssistContent
//                                   sends it as the web URI, see docs/assistant-context.md)
//   help/guide.json, help/routes.json, help/guide.<lang>.md  → machine-readable copies
//   .nojekyll                     → serve files starting with "_" / keep Pages from running Jekyll
import { readFileSync, writeFileSync, mkdirSync, copyFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { renderMarkdown } from './export-help-markdown.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const GUIDE_PATH = process.env.SAMAROH_GUIDE_PATH || join(ROOT, 'help', 'guide.json');
const args = process.argv.slice(2);
const outIdx = args.indexOf('--out');
const OUT = outIdx >= 0 ? args[outIdx + 1] : join(ROOT, 'build', 'help-site');

const guide = JSON.parse(readFileSync(GUIDE_PATH, 'utf8'));
const DEFAULT_LANG = guide.languages.includes('hi') ? 'hi' : guide.languages[0];
const BASE = guide.site.baseUrl; // https://…/help/

const UI = {
  en: {
    siteTitle: 'Samaroh help',
    tagline: 'How to do things in the Samaroh app - step by step.',
    allTopics: 'All topics',
    tasks: 'Tasks on this screen',
    permission: 'Needs permission',
    platformOnly: { android: 'Phone app only', web: 'Web only' },
    stepPlatform: { android: 'phone', web: 'web' },
    otherLang: 'हिन्दी में पढ़ें',
    otherLangCode: 'hi',
    search: 'Search help',
    noResults: 'Nothing found. Try another word.',
    back: 'Back to all topics',
    openInApp: 'App screen',
    tip: 'Tip: on the phone, press and hold any icon button to see its name.',
    footer: 'Generated from samaroh-shared/help/guide.json',
  },
  hi: {
    siteTitle: 'समारोह सहायता',
    tagline: 'समारोह ऐप में काम कैसे करें - एक-एक कदम।',
    allTopics: 'सभी विषय',
    tasks: 'इस स्क्रीन पर काम',
    permission: 'अनुमति चाहिए',
    platformOnly: { android: 'सिर्फ़ फ़ोन ऐप में', web: 'सिर्फ़ वेब पर' },
    stepPlatform: { android: 'फ़ोन', web: 'वेब' },
    otherLang: 'Read in English',
    otherLangCode: 'en',
    search: 'सहायता में खोजें',
    noResults: 'कुछ नहीं मिला। कोई और शब्द आज़माएँ।',
    back: 'सभी विषयों पर वापस',
    openInApp: 'ऐप स्क्रीन',
    tip: 'सुझाव: फ़ोन पर किसी भी चिह्न बटन को दबाकर रखें, उसका नाम दिख जाएगा।',
    footer: 'samaroh-shared/help/guide.json से बनाया गया',
  },
};

const esc = (s) =>
  String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

const CSS = `
:root{color-scheme:light dark;--accent:#6750A4;--bg:#fffbfe;--fg:#1c1b1f;--muted:#5f5b66;--card:#f3edf7;--border:#cac4d0}
@media (prefers-color-scheme:dark){:root{--bg:#1c1b1f;--fg:#e6e1e5;--muted:#cac4d0;--card:#2b2930;--border:#49454f}}
*{box-sizing:border-box}html{font-size:19px}
body{margin:0;background:var(--bg);color:var(--fg);font-family:system-ui,"Noto Sans","Noto Sans Devanagari",sans-serif;line-height:1.6}
header{background:var(--accent);color:#fff;padding:14px 18px}
header a{color:#fff;text-decoration:none}header .brand{font-weight:700;font-size:1.15rem}
header nav{display:flex;gap:16px;flex-wrap:wrap;font-size:.95rem;margin-top:4px}
main{max-width:820px;margin:0 auto;padding:18px}
h1{font-size:1.7rem;margin:.4em 0 .2em}h2{font-size:1.3rem;margin:1.4em 0 .4em;color:var(--accent)}
.summary{font-size:1.05rem;margin:.2em 0 1em}
.card{background:var(--card);border:1px solid var(--border);border-radius:16px;padding:14px 18px;margin:14px 0}
.card h2{margin:0 0 .3em}
ol{padding-left:1.4em}li{margin:.45em 0}
.badge{display:inline-block;font-size:.8rem;padding:1px 10px;border-radius:999px;border:1px solid var(--border);color:var(--muted);margin-left:6px;vertical-align:middle}
.topics a{display:block;padding:14px 18px;margin:10px 0;background:var(--card);border:1px solid var(--border);border-radius:16px;color:var(--fg);text-decoration:none;font-size:1.1rem}
.topics a small{display:block;color:var(--muted);font-size:.9rem}
input[type=search]{width:100%;font-size:1.05rem;padding:12px 14px;border-radius:12px;border:1px solid var(--border);background:var(--bg);color:var(--fg)}
.muted{color:var(--muted)}.tip{font-size:.95rem}
footer{margin:40px 0 20px;color:var(--muted);font-size:.85rem;text-align:center}
`;

function page({ lang, title, description, body, canonical, altUrl, jsonLd }) {
  const ui = UI[lang];
  return `<!doctype html>
<html lang="${lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)} - ${esc(ui.siteTitle)}</title>
<meta name="description" content="${esc(description)}">
<link rel="canonical" href="${canonical}">
<link rel="alternate" hreflang="${ui.otherLangCode}" href="${altUrl}">
<meta name="robots" content="index,follow">
<style>${CSS}</style>
<script type="application/ld+json">${JSON.stringify(jsonLd)}</script>
</head>
<body>
<header>
  <a class="brand" href="${BASE}${lang}/index.html">${esc(ui.siteTitle)}</a>
  <nav><a href="${BASE}${lang}/index.html">${esc(ui.allTopics)}</a><a href="${altUrl}">${esc(ui.otherLang)}</a></nav>
</header>
<main>
${body}
<footer>${esc(ui.footer)}</footer>
</main>
</body>
</html>
`;
}

function screenPage(lang, screen) {
  const ui = UI[lang];
  const canonical = `${BASE}${lang}/${screen.id}.html`;
  const altUrl = `${BASE}${ui.otherLangCode}/${screen.id}.html`;
  const parts = [];
  parts.push(`<p><a href="${BASE}${lang}/index.html">‹ ${esc(ui.back)}</a></p>`);
  parts.push(
    `<h1>${esc(screen.title[lang])}${screen.platforms?.length === 1 ? `<span class="badge">${esc(ui.platformOnly[screen.platforms[0]])}</span>` : ''}</h1>`,
  );
  parts.push(`<p class="summary">${esc(screen.summary[lang])}</p>`);
  parts.push(`<p class="muted tip">${esc(ui.tip)}</p>`);
  parts.push(`<h2 class="muted" style="color:var(--muted);font-size:1rem">${esc(ui.tasks)}</h2>`);
  for (const t of screen.tasks) {
    parts.push(`<section class="card" id="${esc(t.id)}">`);
    parts.push(
      `<h2>${esc(t.title[lang])}${t.platforms?.length === 1 ? `<span class="badge">${esc(ui.platformOnly[t.platforms[0]])}</span>` : ''}</h2>`,
    );
    if (t.permission) parts.push(`<p class="muted" style="font-size:.9rem">${esc(ui.permission)}: <code>${esc(t.permission)}</code></p>`);
    parts.push('<ol>');
    for (const step of t.steps) {
      const tag = step.platforms?.length === 1 ? `<span class="badge">${esc(ui.stepPlatform[step.platforms[0]])}</span>` : '';
      parts.push(`<li>${esc(step[lang])}${tag}</li>`);
    }
    parts.push('</ol></section>');
  }
  const jsonLd = {
    '@context': 'https://schema.org',
    '@type': 'WebPage',
    name: screen.title[lang],
    description: screen.summary[lang],
    inLanguage: lang,
    url: canonical,
    isPartOf: { '@type': 'WebSite', name: ui.siteTitle, url: `${BASE}${lang}/index.html` },
    hasPart: screen.tasks.map((t) => ({
      '@type': 'HowTo',
      name: t.title[lang],
      step: t.steps
        .filter((s) => !s.platforms || s.platforms.includes('android'))
        .map((s, i) => ({ '@type': 'HowToStep', position: i + 1, text: s[lang] })),
    })),
  };
  return page({ lang, title: screen.title[lang], description: screen.summary[lang], body: parts.join('\n'), canonical, altUrl, jsonLd });
}

function indexPage(lang) {
  const ui = UI[lang];
  const canonical = `${BASE}${lang}/index.html`;
  const altUrl = `${BASE}${ui.otherLangCode}/index.html`;
  const parts = [];
  parts.push(`<h1>${esc(ui.siteTitle)}</h1><p class="summary">${esc(ui.tagline)}</p>`);
  parts.push(`<input type="search" id="q" placeholder="${esc(ui.search)}" aria-label="${esc(ui.search)}" autocomplete="off">`);
  parts.push('<div class="topics" id="topics">');
  for (const s of guide.screens) {
    const haystack = [s.title[lang], s.summary[lang], ...s.tasks.flatMap((t) => [t.title[lang], ...t.steps.map((st) => st[lang])])].join(' ');
    parts.push(
      `<a href="${BASE}${lang}/${s.id}.html" data-text="${esc(haystack.toLowerCase())}">${esc(s.title[lang])}<small>${esc(
        s.tasks.map((t) => t.title[lang]).join(' · '),
      )}</small></a>`,
    );
  }
  parts.push('</div>');
  parts.push(`<p class="muted" id="none" hidden>${esc(ui.noResults)}</p>`);
  parts.push(`<script>
(function(){var q=document.getElementById('q'),links=[].slice.call(document.querySelectorAll('#topics a')),none=document.getElementById('none');
q.addEventListener('input',function(){var v=q.value.trim().toLowerCase(),n=0;links.forEach(function(a){var hit=!v||a.getAttribute('data-text').indexOf(v)>=0;a.hidden=!hit;if(hit)n++;});none.hidden=n>0;});})();
</script>`);
  const jsonLd = {
    '@context': 'https://schema.org',
    '@type': 'WebSite',
    name: ui.siteTitle,
    description: ui.tagline,
    inLanguage: lang,
    url: canonical,
  };
  return page({ lang, title: ui.allTopics, description: ui.tagline, body: parts.join('\n'), canonical, altUrl, jsonLd });
}

function redirect(to) {
  return `<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="refresh" content="0;url=${to}"><link rel="canonical" href="${to}"><title>Samaroh help</title></head><body><a href="${to}">${to}</a></body></html>\n`;
}

mkdirSync(join(OUT, 'help'), { recursive: true });
writeFileSync(join(OUT, '.nojekyll'), '');
writeFileSync(join(OUT, 'index.html'), redirect(`${BASE}${DEFAULT_LANG}/index.html`));
writeFileSync(join(OUT, 'help', 'index.html'), redirect(`${BASE}${DEFAULT_LANG}/index.html`));
copyFileSync(GUIDE_PATH, join(OUT, 'help', 'guide.json'));
copyFileSync(join(ROOT, 'help', 'routes.json'), join(OUT, 'help', 'routes.json'));
let pages = 0;
for (const lang of guide.languages) {
  const dir = join(OUT, 'help', lang);
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'index.html'), indexPage(lang));
  writeFileSync(join(OUT, 'help', `guide.${lang}.md`), renderMarkdown(lang));
  for (const s of guide.screens) {
    writeFileSync(join(dir, `${s.id}.html`), screenPage(lang, s));
    pages += 1;
  }
}
console.log(`Built help site: ${pages} screen pages + ${guide.languages.length} indexes → ${OUT}`);
