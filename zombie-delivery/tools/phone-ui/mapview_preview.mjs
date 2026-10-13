// 7.2: draws mapview.luau's recorded scenes (the real MapView's instance tree: frames, text, corners, strokes,
// gradients, scales, rotations, ZIndex) as positioned elements in headless Chromium, one PNG a scene. Not Roblox's
// renderer: the fonts are stand-ins and TextScaled is fitted by measuring; enough to see the map's look and layout.
// Usage (mapview_preview.py runs it): node mapview_preview.mjs <scenes.json> <out dir> [font.woff2]
// Playwright from NODE_PATH (e.g. /opt/node22/lib/node_modules), Chromium from CHROMIUM (/opt/pw-browsers/chromium).
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const [scenesFile, outDir, fontFile] = process.argv.slice(2);
const scenes = JSON.parse(fs.readFileSync(scenesFile, 'utf8'));
fs.mkdirSync(outDir, { recursive: true });
const font = fontFile && fs.existsSync(fontFile) ? `data:font/woff2;base64,${fs.readFileSync(fontFile).toString('base64')}` : null;

// Runs in the page: builds one scene's tree under <body>.
function render(scene, font) {
  document.body.innerHTML = '';
  if (font && !document.getElementById('face')) {
    const style = document.createElement('style');
    style.id = 'face';
    style.textContent = `@font-face { font-family: Gotham; src: url(${font}); font-weight: 100 900; }`;
    document.head.appendChild(style);
  }
  const FONTS = 'Gotham, "DejaVu Sans", "Noto Color Emoji", sans-serif';
  const DEFAULTS = {
    Frame: { bg: [163, 162, 165], bgT: 0 },
    CanvasGroup: { bg: [163, 162, 165], bgT: 0 },
    ScrollingFrame: { bg: [163, 162, 165], bgT: 0 },
    TextLabel: { bg: [255, 255, 255], bgT: 0, tc: [0, 0, 0], ts: 14 },
    TextButton: { bg: [255, 255, 255], bgT: 0, tc: [0, 0, 0], ts: 14 },
  };
  const rgba = (c, t) => `rgba(${c[0]},${c[1]},${c[2]},${1 - (t || 0)})`;
  const canvas = document.createElement('canvas').getContext('2d');
  const weight = f => (f && /Black/.test(f) ? 900 : f && /Bold|Heading/.test(f) ? 700 : 500);
  const width = (text, size, f) => {
    canvas.font = `${weight(f)} ${size}px ${FONTS}`;
    return canvas.measureText(text.replace(/<[^>]+>/g, '')).width;
  };
  const isGui = n => !n.c.startsWith('UI') && n.c !== 'ScreenGui' && n.c !== 'PlayerGui';
  function build(n, parent, pw, ph) {
    if (!isGui(n) && n.c !== 'ScreenGui') return;
    const d = DEFAULTS[n.c] || {};
    const size = n.size || [0, 0, 0, 0];
    const pos = n.pos || [0, 0, 0, 0];
    const anchor = n.anchor || [0, 0];
    const w = n.c === 'ScreenGui' ? pw : pw * size[0] + size[1];
    const h = n.c === 'ScreenGui' ? ph : ph * size[2] + size[3];
    const el = document.createElement('div');
    el.style.cssText = 'position:absolute;box-sizing:border-box;';
    if (n.c !== 'ScreenGui') {
      el.style.left = `${pw * pos[0] + pos[1] - anchor[0] * w}px`;
      el.style.top = `${ph * pos[2] + pos[3] - anchor[1] * h}px`;
    } else {
      el.style.left = '0px';
      el.style.top = '0px';
    }
    el.style.width = `${w}px`;
    el.style.height = `${h}px`;
    if (n.vis === false) el.style.display = 'none';
    el.style.zIndex = String(n.z ?? 1);
    const bg = n.bg || d.bg;
    const bgT = n.bgT ?? d.bgT ?? 1;
    if (bg && bgT < 1) el.style.backgroundColor = rgba(bg, bgT);
    if (n.clip || n.c === 'CanvasGroup' || n.c === 'ScrollingFrame') el.style.overflow = 'hidden';
    const kids = n.kids || [];
    const transforms = [];
    let origin = 'center';
    for (const k of kids) {
      if (k.c === 'UICorner') {
        const r = Math.min(k.radius[0] * Math.min(w, h) + k.radius[1], Math.min(w, h) / 2);
        el.style.borderRadius = `${Math.max(0, r)}px`;
      } else if (k.c === 'UIStroke') {
        el.style.boxShadow = `0 0 0 ${k.thick ?? 1}px ${rgba(k.color || [0, 0, 0], k.tr || 0)}`;
      } else if (k.c === 'UIGradient') {
        const angle = 90 + (k.rot || 0);
        if (k.colors && k.colors[0] && el.style.backgroundColor) {
          el.style.backgroundImage = `linear-gradient(${angle}deg, rgb(${k.colors[0]}), rgb(${k.colors[1]}))`;
          el.style.backgroundBlendMode = 'multiply';
        }
        if (k.tr) {
          const stops = k.tr.map(([t, v]) => `rgba(0,0,0,${1 - v}) ${t * 100}%`).join(',');
          el.style.webkitMaskImage = el.style.maskImage = `linear-gradient(${angle}deg, ${stops})`;
        }
      } else if (k.c === 'UIScale') {
        transforms.push(`scale(${k.scale ?? 1})`);
        origin = `${anchor[0] * 100}% ${anchor[1] * 100}%`;
      }
    }
    if (n.rot) transforms.unshift(`rotate(${n.rot}deg)`);
    if (transforms.length) {
      el.style.transform = transforms.join(' ');
      el.style.transformOrigin = origin;
    }
    if (n.text) {
      const span = document.createElement('div');
      const f = n.font || 'GothamBold';
      let ts = n.ts || d.ts || 14;
      if (n.scaled) {
        const one = width(n.text, 100, f) / 100 || 1;
        ts = Math.max(1, Math.min(h * 0.92, (w * 0.98) / one, 100));
      }
      const tc = n.tc || d.tc || [0, 0, 0];
      const left = n.xa === 'Left';
      span.style.cssText = `position:absolute;inset:0;display:flex;align-items:center;justify-content:${left ? 'flex-start' : 'center'};` +
        `white-space:nowrap;overflow:visible;font-family:${FONTS};font-weight:${weight(f)};font-size:${ts}px;line-height:1;color:${rgba(tc, n.tt || 0)};`;
      if (n.st !== undefined && n.st < 1 && n.sc) {
        const s = rgba(n.sc, n.st);
        span.style.textShadow = `1px 0 ${s},-1px 0 ${s},0 1px ${s},0 -1px ${s}`;
      }
      if (n.rich) span.innerHTML = n.text.replace(/<font color="(#[0-9A-Fa-f]{6})">/g, '<span style="color:$1">').replace(/<\/font>/g, '</span>');
      else span.textContent = n.text;
      el.appendChild(span);
    }
    parent.appendChild(el);
    const list = kids.find(k => k.c === 'UIListLayout');
    if (list) {
      let y = 6;
      const items = kids.filter(k => isGui(k) && k.vis !== false).sort((a, b) => (a.order || 0) - (b.order || 0));
      for (const k of items) {
        const kh = (k.size || [0, 0, 0, 0])[2] * h + (k.size || [0, 0, 0, 0])[3];
        build({ ...k, pos: [0, 6, 0, y], anchor: [0, 0] }, el, w, h);
        y += kh + (list.pad || 0);
      }
      for (const k of kids) if (isGui(k) && !items.includes(k)) build(k, el, w, h);
    } else {
      for (const k of kids) build(k, el, w, h);
    }
  }
  const stage = document.createElement('div');
  stage.style.cssText = `position:absolute;left:0;top:0;width:${scene.width}px;height:${scene.height}px;overflow:hidden;` +
    'background:linear-gradient(180deg,#8fb3cf 0%,#c9d8df 38%,#7d9468 40%,#5b7048 100%);';
  document.body.appendChild(stage);
  const find = (n, name) => (n.n === name ? n : (n.kids || []).reduce((hit, k) => hit || find(k, name), null));
  const hud = find(scene.tree, 'ZombieDeliveryHud');
  build(hud, stage, scene.width, scene.height);
}

const browser = await chromium.launch({ executablePath: process.env.CHROMIUM || '/opt/pw-browsers/chromium' });
const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
page.on('pageerror', e => console.log('page error:', e.message));
await page.setContent('<!doctype html><html><head><meta charset="utf-8"><style>body{margin:0}</style></head><body></body></html>');
await page.addScriptTag({ content: render.toString() });
for (const scene of scenes) {
  await page.setViewportSize({ width: scene.width, height: scene.height });
  await page.evaluate(([s, f]) => window.render(s, f), [scene, font]);
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(150);
  await page.screenshot({ path: path.join(outDir, `${scene.name}.png`) });
}
console.log('rendered', scenes.length, 'scenes');
await browser.close();
