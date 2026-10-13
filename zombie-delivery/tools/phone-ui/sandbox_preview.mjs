// 8.0 SANDBOX: draws sandbox.luau's recorded scenes (the real SandboxHud / WarehouseUi instance trees: frames, text,
// corners, strokes, paddings, scales, scrolling frames, ViewportFrames, ZIndex) as positioned elements in headless
// Chromium, one PNG a scene, over a stand-in of the world, Roblox's top bar and (touch) its thumbstick, the jump button
// and the HUD's touch buttons. Not Roblox's renderer: the fonts are stand-ins and a 3D picture (a ViewportFrame) is drawn
// as its piece's emoji on a lit backdrop; enough to see the layout and the look.
// Usage (sandbox_preview.py runs it): node sandbox_preview.mjs <scenes.json> <out dir> [font dir with montserrat-500/700.woff2]
// Playwright from NODE_PATH (e.g. /opt/node22/lib/node_modules), Chromium from CHROMIUM (/opt/pw-browsers/chromium).
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const [scenesFile, outDir, fontDir] = process.argv.slice(2);
const scenes = JSON.parse(fs.readFileSync(scenesFile, 'utf8'));
fs.mkdirSync(outDir, { recursive: true });
const fonts = {};
for (const weight of [500, 700]) {
  const file = fontDir && path.join(fontDir, `montserrat-${weight}.woff2`);
  if (file && fs.existsSync(file)) fonts[weight] = `data:font/woff2;base64,${fs.readFileSync(file).toString('base64')}`;
}

// Runs in the page: builds one scene under <body>.
function render(scene, fonts) {
  document.body.innerHTML = '';
  if (!document.getElementById('faces')) {
    const style = document.createElement('style');
    style.id = 'faces';
    style.textContent = Object.entries(fonts).map(([w, url]) => `@font-face { font-family: Gotham; src: url(${url}); font-weight: ${w}; }`).join('\n');
    document.head.appendChild(style);
  }
  const FONTS = 'Gotham, "DejaVu Sans", "Noto Color Emoji", sans-serif';
  const DEFAULTS = {
    Frame: { bg: [163, 162, 165], bgT: 0 },
    CanvasGroup: { bg: [163, 162, 165], bgT: 0 },
    ScrollingFrame: { bg: [163, 162, 165], bgT: 0 },
    ViewportFrame: { bg: [163, 162, 165], bgT: 0 },
    TextLabel: { bg: [255, 255, 255], bgT: 0, tc: [0, 0, 0], ts: 14 },
    TextButton: { bg: [255, 255, 255], bgT: 0, tc: [0, 0, 0], ts: 14 },
  };
  const rgba = (c, t) => `rgba(${c[0]},${c[1]},${c[2]},${1 - (t || 0)})`;
  const weight = f => (f && /Bold|Black|Heading/.test(f) ? 700 : 500);
  const isGui = n => !n.c.startsWith('UI') && !['ScreenGui', 'PlayerGui', 'Camera', 'Model', 'Part', 'Player'].includes(n.c);
  function build(n, parent, pw, ph, ox, oy) {
    if (!isGui(n)) return;
    const d = DEFAULTS[n.c] || {};
    const size = n.size || [0, 0, 0, 0];
    const pos = n.pos || [0, 0, 0, 0];
    const anchor = n.anchor || [0, 0];
    const kids = n.kids || [];
    const scaleKid = kids.find(k => k.c === 'UIScale');
    const own = scaleKid ? scaleKid.scale ?? 1 : 1;
    const w = pw * size[0] + size[1];
    const h = ph * size[2] + size[3];
    const el = document.createElement('div');
    el.style.cssText = 'position:absolute;box-sizing:border-box;';
    el.style.left = `${ox + pw * pos[0] + pos[1] - anchor[0] * w * own}px`;
    el.style.top = `${oy + ph * pos[2] + pos[3] - anchor[1] * h * own}px`;
    el.style.width = `${w}px`;
    el.style.height = `${h}px`;
    if (own !== 1) {
      el.style.transform = `scale(${own})`;
      el.style.transformOrigin = '0 0';
    }
    if (n.vis === false) el.style.display = 'none';
    el.style.zIndex = String(n.z ?? 1);
    const bg = n.bg || d.bg;
    const bgT = n.bgT ?? d.bgT ?? 1;
    if (bg && bgT < 1) el.style.backgroundColor = rgba(bg, bgT);
    if (n.clip || n.c === 'CanvasGroup' || n.c === 'ScrollingFrame' || n.c === 'ViewportFrame') el.style.overflow = 'hidden';
    let padL = 0, padR = 0;
    for (const k of kids) {
      if (k.c === 'UICorner') {
        const r = Math.min(k.radius[0] * Math.min(w, h) + k.radius[1], Math.min(w, h) / 2);
        el.style.borderRadius = `${Math.max(0, r)}px`;
      } else if (k.c === 'UIStroke') {
        el.style.boxShadow = `inset 0 0 0 ${k.thick ?? 1}px ${rgba(k.color || [0, 0, 0], k.tr || 0)}`;
      } else if (k.c === 'UIPadding') {
        [padL, padR] = k.pad || [0, 0];
      }
    }
    if (n.c === 'ViewportFrame') {
      // the 3D picture: the piece's emoji on a lit backdrop, a small "3D" mark
      el.style.background = 'radial-gradient(ellipse at 50% 38%, rgba(255,244,226,0.22), rgba(255,244,226,0) 70%)';
      const mark = document.createElement('div');
      const big = Math.floor(Math.min(w, h) * 0.62);
      mark.style.cssText = `position:absolute;inset:0;display:flex;align-items:center;justify-content:center;font-size:${big}px;font-family:${FONTS};filter:drop-shadow(0 4px 3px rgba(0,0,0,0.55));`;
      mark.textContent = n.emoji || '📦';
      el.appendChild(mark);
      const tag = document.createElement('div');
      tag.style.cssText = `position:absolute;right:4px;top:4px;font:700 9px ${FONTS};color:rgba(255,255,255,0.55);`;
      tag.textContent = '3D';
      el.appendChild(tag);
    }
    if (n.text) {
      const box = document.createElement('div');
      const ts = n.ts || d.ts || 14;
      const tc = n.tc || d.tc || [0, 0, 0];
      const justify = n.xa === 'Left' ? 'flex-start' : n.xa === 'Right' ? 'flex-end' : 'center';
      box.style.cssText = `position:absolute;left:${padL}px;right:${padR}px;top:0;bottom:0;display:flex;align-items:center;justify-content:${justify};` +
        `font-family:${FONTS};font-weight:${weight(n.font)};font-size:${ts}px;line-height:1.15;color:${rgba(tc, n.tt || 0)};`;
      const span = document.createElement('span');
      span.textContent = n.text;
      span.style.cssText = n.wrap ? `white-space:normal;text-align:${n.xa === 'Left' ? 'left' : n.xa === 'Right' ? 'right' : 'center'};` :
        n.trunc ? 'white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:100%;' : 'white-space:nowrap;';
      box.appendChild(span);
      el.appendChild(box);
    }
    parent.appendChild(el);
    const scroll = n.c === 'ScrollingFrame' ? n.canvas || [0, 0] : [0, 0];
    for (const k of kids) build(k, el, w - padL - padR, h, padL - scroll[0], -scroll[1]);
  }
  const W = scene.width, H = scene.height, inset = scene.inset || 0;
  const stage = document.createElement('div');
  stage.style.cssText = `position:absolute;left:0;top:0;width:${W}px;height:${H}px;overflow:hidden;` +
    'background:linear-gradient(180deg,#9cc1dc 0%,#d7e4ea 40%,#a3b79a 41%,#7e9a6a 62%,#5f7650 100%);';
  document.body.appendChild(stage);
  // a stand-in of the world: a road, the warehouse's front, the van
  const world = document.createElement('div');
  world.style.cssText = 'position:absolute;inset:0;';
  world.innerHTML = `<div style="position:absolute;left:0;right:0;top:58%;height:14%;background:#55585c"></div>
    <div style="position:absolute;left:${W * 0.52}px;top:${H * 0.2}px;width:${W * 0.36}px;height:${H * 0.38}px;background:#c9cdd1;box-shadow:inset 0 -6px 0 #a3a8ad"></div>
    <div style="position:absolute;left:${W * 0.6}px;top:${H * 0.3}px;width:${W * 0.18}px;height:${H * 0.28}px;background:repeating-linear-gradient(180deg,#8d9399 0 6px,#7b8187 6px 8px)"></div>
    <div style="position:absolute;left:${W * 0.55}px;top:${H * 0.12}px;width:${W * 0.08}px;height:${H * 0.06}px;background:#d74a46;color:#fff;font:700 ${Math.max(10, H * 0.035)}px sans-serif;display:flex;align-items:center;justify-content:center">ZDC</div>
    <div style="position:absolute;left:${W * 0.25}px;top:${H * 0.44}px;width:${W * 0.2}px;height:${H * 0.2}px;background:#f2f2f0;border-radius:8px 18px 6px 6px;box-shadow:inset -${W * 0.05}px 0 0 #e1e3e5"></div>`;
  stage.appendChild(world);
  // Roblox's top bar (the GUI starts under it)
  const bar = document.createElement('div');
  bar.style.cssText = `position:absolute;left:0;top:0;width:${W}px;height:${inset}px;background:rgba(0,0,0,0.35);`;
  bar.innerHTML = [12, 52].map(x => `<div style="position:absolute;left:${x}px;top:${(inset - 28) / 2}px;width:28px;height:28px;border-radius:8px;background:rgba(20,20,20,0.7)"></div>`).join('');
  stage.appendChild(bar);
  const area = document.createElement('div');
  area.style.cssText = `position:absolute;left:0;top:${inset}px;width:${W}px;height:${H - inset}px;`;
  stage.appendChild(area);
  // the touch controls (under the windows: a modal card covers them)
  for (const o of scene.overlay || []) {
    const b = o.box;
    const el = document.createElement('div');
    const w = b.x1 - b.x0, h = b.y1 - b.y0;
    el.style.cssText = `position:absolute;left:${b.x0}px;top:${b.y0}px;width:${w}px;height:${h}px;box-sizing:border-box;display:flex;align-items:center;justify-content:center;` +
      `font:700 ${Math.max(9, Math.min(13, h * 0.25))}px ${FONTS};color:rgba(255,255,255,0.85);z-index:0;`;
    if (o.kind === 'stick') {
      el.innerHTML = `<div style="width:${Math.min(w, h) * 0.62}px;height:${Math.min(w, h) * 0.62}px;border-radius:50%;border:2px solid rgba(255,255,255,0.45);background:rgba(0,0,0,0.18)"></div>`;
    } else if (o.kind === 'minimap') {
      el.style.alignItems = 'flex-end';
      el.innerHTML = `<div style="width:100%;height:${Math.min(22, h * 0.2)}px;border-radius:3px;background:rgba(20,23,28,0.7);box-shadow:inset 0 0 0 1px rgba(133,139,147,0.5)"><div style="width:72%;height:100%;background:#7ec478;border-radius:3px"></div></div>`;
      el.title = 'health';
    } else if (o.kind === 'text') {
      el.style.justifyContent = 'flex-end';
      el.textContent = o.label || '';
    } else if (o.kind === 'chat') {
      el.style.cssText += 'background:rgba(25,27,29,0.6);border-radius:6px;align-items:flex-start;justify-content:flex-start;padding:10px;font-weight:500;flex-direction:column;';
      el.innerHTML = ['Ann: nice van', 'Courier: brb, warehouse', '[System] Welcome to Zombie Delivery'].map(s => `<div style="margin-bottom:6px">${s}</div>`).join('');
    } else {
      el.style.borderRadius = o.kind === 'round' ? '50%' : '10px';
      el.style.background = 'rgba(20,23,28,0.55)';
      el.style.boxShadow = 'inset 0 0 0 1px rgba(255,255,255,0.35)';
      el.textContent = o.label || '';
    }
    area.appendChild(el);
  }
  const guis = (scene.tree.kids || []).filter(k => k.c === 'ScreenGui' && k.enabled !== false).sort((a, b) => (a.display || 0) - (b.display || 0));
  let layer = 10;
  for (const g of guis) {
    const holder = document.createElement('div');
    holder.style.cssText = `position:absolute;inset:0;z-index:${layer++};`;
    area.appendChild(holder);
    for (const k of g.kids || []) build(k, holder, W, H - inset, 0, 0);
  }
}

const browser = await chromium.launch({ executablePath: process.env.CHROMIUM || '/opt/pw-browsers/chromium' });
const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
page.on('pageerror', e => console.log('page error:', e.message));
await page.setContent('<!doctype html><html><head><meta charset="utf-8"><style>body{margin:0}</style></head><body></body></html>');
await page.addScriptTag({ content: render.toString() });
for (const scene of scenes) {
  await page.setViewportSize({ width: scene.width, height: scene.height });
  await page.evaluate(([s, f]) => window.render(s, f), [scene, fonts]);
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(150);
  await page.screenshot({ path: path.join(outDir, `${scene.name}.png`) });
}
console.log('rendered', scenes.length, 'scenes');
await browser.close();
