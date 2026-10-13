// 7.0, the moving prototype: renders export.luau's JSON lines with three.js in headless Chromium (render.html): every
// piece as <out>/<name>.png, the house from above (<out>/house-top.png) and as a 3/4 cutaway (<out>/house-iso.png),
// with labels.json (the pieces' catalogue entries, where the rooms and pieces land on the house pictures). 7.x the
// farm: a scene of layout "farm" as <out>/farm-top.png and <out>/farm-iso.png (labels.farm), taller pictures.
// Usage (render.py runs it): node render.mjs <scenes.jsonl> <out dir> <dir with render.html and three.module.min.js>
// Playwright from NODE_PATH (e.g. /opt/node22/lib/node_modules), Chromium from CHROMIUM (default /opt/pw-browsers/chromium).
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const [source, outDir, root] = process.argv.slice(2);
const scenes = fs.readFileSync(source, 'utf8').split('\n').filter(Boolean).map(l => JSON.parse(l));
fs.mkdirSync(outDir, { recursive: true });

const server = http.createServer((req, res) => {
  const file = path.join(root, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  if (!file.startsWith(root) || !fs.existsSync(file)) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'Content-Type': file.endsWith('.js') ? 'text/javascript' : 'text/html' });
  fs.createReadStream(file).pipe(res);
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM || '/opt/pw-browsers/chromium',
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
});
const page = await browser.newPage({ viewport: { width: 1400, height: 1200 } });
page.on('pageerror', e => console.log('page error:', e.message));
page.on('console', m => { if (m.type() === 'error') console.log('console:', m.text()); });
await page.goto(`http://127.0.0.1:${server.address().port}/render.html`);
await page.waitForFunction(() => window.ready === true);
const labels = { items: {}, house: null, farm: null };
for (const scene of scenes) {
  if (scene.kind === 'item') {
    await page.evaluate(s => window.renderItem(s, 360), scene);
    await page.locator('canvas').screenshot({ path: path.join(outDir, `${scene.name}.png`) });
    labels.items[scene.name] = scene.info;
  } else {
    const key = scene.layout === 'farm' ? 'farm' : 'house';
    const [tw, th, iw, ih] = key === 'farm' ? [900, 1120, 1300, 1120] : [1000, 900, 1200, 900];
    const top = await page.evaluate(([s, w, h]) => window.renderHouse(s, 'top', w, h), [scene, tw, th]);
    await page.locator('canvas').screenshot({ path: path.join(outDir, `${key}-top.png`) });
    const iso = await page.evaluate(([s, w, h]) => window.renderHouse(s, 'iso', w, h), [scene, iw, ih]);
    await page.locator('canvas').screenshot({ path: path.join(outDir, `${key}-iso.png`) });
    labels[key] = { info: { ...scene.info, lights: undefined }, top, iso };
  }
}
fs.writeFileSync(path.join(outDir, 'labels.json'), JSON.stringify(labels, null, 1));
console.log('rendered', scenes.length);
await browser.close();
server.close();
