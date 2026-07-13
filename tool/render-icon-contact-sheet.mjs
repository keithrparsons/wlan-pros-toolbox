// Contact-sheet renderer for the v1.1 tool-icon completion set.
// Production render path: headless Chrome via puppeteer-core (NEVER ImageMagick,
// which silently drops stroke on fill:none paths — GL-003 §8.6.1). Renders the
// full set + a zoom strip of the 8 new icons, in dark (lime on #222222) and
// light (darkened-lime #5A7A1C on white, per §8.20.7) at the 20px legibility
// floor and 24px nav size.
import { promises as fs } from 'fs';
import path from 'path';
import puppeteer from '/Users/keithparsons/.npm/_npx/7d92d9a2d2ccc630/node_modules/puppeteer-core/lib/puppeteer/puppeteer-core.js';

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
// ROOT resolves to the repo root from this file's location (tool/...), so the
// renderer works in any worktree. Previously hardcoded to a non-existent
// '/Users/keithparsons/Developer/wlan_pros_toolbox-v11icons' path.
const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const DIR = path.join(ROOT, 'assets/tool-icons');
const OUT = path.join(ROOT, 'tool/icon-contact-sheets');
await fs.mkdir(OUT, { recursive: true });

// The three v1.1.1 polish icons under re-gate.
const NEW = new Set([
  'antenna-fundamentals','wifi-exposure-perspective',
]);

// Each v1.1.1 icon shown beside the neighbors that share its visual vocabulary,
// so Vera can judge silhouette differentiation at the legibility floor.
const FOCUS = [
  'antenna-fundamentals','eirp','downtilt-coverage','antenna-connectors',
  'wifi-exposure-perspective','freeradius-wlanpi',
];

const files = (await fs.readdir(DIR)).filter(f => f.endsWith('.svg')).sort();
const svgs = {};
for (const f of files) svgs[f] = await fs.readFile(path.join(DIR, f), 'utf8');

function grid(list, { icColor, cellBg, cellBorder, lblColor, newBorder }) {
  return list.map(f => {
    const isNew = NEW.has(f.replace('.svg',''));
    return `<div class="cell" style="background:${cellBg};border:1px solid ${isNew ? newBorder : cellBorder}">
      <div class="ic" style="color:${icColor}">
        <span class="s20">${svgs[f]}</span>
        <span class="s24">${svgs[f]}</span>
      </div>
      <div class="lbl" style="color:${lblColor}">${f.replace('.svg','')}${isNew ? ' ●' : ''}</div>
    </div>`;
  }).join('');
}

// Focused side-by-side: v1.1.1 icons beside their neighbors, at BOTH the 20px
// legibility floor and 72px, so a redraw can be judged tiny and large at once.
function focusGrid(list, { icColor, cellBg, cellBorder, lblColor, newBorder }) {
  return list.map(f => {
    const fn = f + '.svg';
    const isNew = NEW.has(f);
    return `<div class="cell" style="background:${cellBg};border:1px solid ${isNew ? newBorder : cellBorder}">
      <div class="fic" style="color:${icColor}">
        <span class="f20">${svgs[fn]}</span>
        <span class="f72">${svgs[fn]}</span>
      </div>
      <div class="lbl" style="color:${lblColor}">${f}${isNew ? ' ●' : ''}</div>
    </div>`;
  }).join('');
}

function focusSheet(title, sub, theme) {
  return `<section style="background:${theme.pageBg};padding:24px">
    <h1 style="color:${theme.h1};font-size:18px;margin:0 0 4px;font-family:system-ui">${title}</h1>
    <p style="color:${theme.sub};font-size:12px;margin:0 0 18px;font-family:system-ui">${sub}</p>
    <div class="fgrid">${focusGrid(FOCUS, theme)}</div>
  </section>`;
}

function sheet(title, sub, theme, list) {
  return `<section style="background:${theme.pageBg};padding:24px">
    <h1 style="color:${theme.h1};font-size:18px;margin:0 0 4px;font-family:system-ui">${title}</h1>
    <p style="color:${theme.sub};font-size:12px;margin:0 0 18px;font-family:system-ui">${sub}</p>
    <div class="grid">${grid(list, theme)}</div>
  </section>`;
}

const dark = { pageBg:'#222222', h1:'#A2CC3A', sub:'#9C9C9C', icColor:'#A2CC3A',
  cellBg:'#2b2b2b', cellBorder:'#3a3a3a', lblColor:'#cfcfcf', newBorder:'#A2CC3A' };
const light = { pageBg:'#FFFFFF', h1:'#2F5E00', sub:'#444444', icColor:'#5A7A1C',
  cellBg:'#F7F7F5', cellBorder:'#E5E5E5', lblColor:'#444444', newBorder:'#5A7A1C' };

const css = `<style>
  *{box-sizing:border-box} body{margin:0;font-family:system-ui,-apple-system,sans-serif}
  .grid{display:grid;grid-template-columns:repeat(8,1fr);gap:12px}
  .cell{border-radius:10px;padding:12px 6px;text-align:center}
  .ic{height:44px;display:flex;align-items:center;justify-content:center;gap:10px}
  .ic .s20 svg{width:20px;height:20px} .ic .s24 svg{width:24px;height:24px}
  .lbl{font-size:9px;margin-top:8px;word-break:break-word;line-height:1.25}
  .zoom .grid{grid-template-columns:repeat(8,1fr)}
  .zoom .ic{height:80px} .zoom .ic .s20 svg{width:48px;height:48px} .zoom .ic .s24 svg{display:none}
  .zoom .lbl{font-size:11px}
  .fgrid{display:grid;grid-template-columns:repeat(7,1fr);gap:14px}
  .fic{height:96px;display:flex;align-items:center;justify-content:center;gap:14px}
  .fic .f20 svg{width:20px;height:20px} .fic .f72 svg{width:72px;height:72px}
</style>`;

const html = `<!doctype html><html><head><meta charset="utf-8">${css}</head><body>
  ${focusSheet('v1.1.1 polish — three icons beside neighbors · 20px + 72px · DARK',
    'antenna-fundamentals, wifi-exposure-perspective (●) beside their visual-vocabulary neighbors · lime #A2CC3A on app surface #222222 · each cell: 20px floor (left) + 72px (right)',
    dark)}
  ${focusSheet('v1.1.1 polish — three icons beside neighbors · 20px + 72px · LIGHT',
    'darkened-lime #5A7A1C on white (§8.20.7) · each cell: 20px floor (left) + 72px (right)',
    light)}
  ${sheet(`WLAN Pros Toolbox — Full Tier-2 Icon Set (${files.length} icons) · DARK`,
    'Each cell shows the glyph at the 20px legibility floor AND 24px nav size · lime #A2CC3A on app surface #222222 · ● = new in v1.1',
    dark, files)}
  ${sheet(`Full Tier-2 Icon Set (${files.length} icons) · LIGHT`,
    '20px + 24px · darkened-lime #5A7A1C on white (§8.20.7 light treatment) · ● = new in v1.1',
    light, files)}
  <section class="zoom" style="background:#222222;padding:24px">
    <h1 style="color:#A2CC3A;font-size:18px;margin:0 0 4px;font-family:system-ui">The 8 new icons — zoom (48px), DARK</h1>
    <p style="color:#9C9C9C;font-size:12px;margin:0 0 18px;font-family:system-ui">Eyeball for house-style consistency and silhouette differentiation vs siblings</p>
    <div class="grid">${grid([...NEW].map(n=>n+'.svg').sort(), dark)}</div>
  </section>
  <section class="zoom" style="background:#FFFFFF;padding:24px">
    <h1 style="color:#2F5E00;font-size:18px;margin:0 0 4px;font-family:system-ui">The 8 new icons — zoom (48px), LIGHT</h1>
    <p style="color:#444;font-size:12px;margin:0 0 18px;font-family:system-ui">darkened-lime #5A7A1C on white</p>
    <div class="grid">${grid([...NEW].map(n=>n+'.svg').sort(), light)}</div>
  </section>
</body></html>`;

const htmlPath = path.join(OUT, 'contact-sheet.html');
await fs.writeFile(htmlPath, html);

const browser = await puppeteer.launch({ executablePath: CHROME, headless: 'new', args:['--no-sandbox'] });
const page = await browser.newPage();
await page.setViewport({ width: 1280, height: 1400, deviceScaleFactor: 2 });
await page.goto('file://' + htmlPath, { waitUntil: 'networkidle0' });
const pngPath = path.join(OUT, 'tool-icon-contact-sheet.png');
await page.screenshot({ path: pngPath, fullPage: true });
await browser.close();
console.log('rendered', files.length, 'icons (8 new) ->', pngPath);
