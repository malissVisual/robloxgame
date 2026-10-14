// 8.3: draws the sandbox's map sheet (design/sandbox/map.png) in headless Chromium: compose.js lays it out, render.html
// draws the parts with three.js. Usage (render.py runs it):
//   node render.mjs <world.json> <facts.json> <fleet.json> <out.png> <site dir> <label>
// Playwright from NODE_PATH (e.g. /opt/node22/lib/node_modules), Chromium from CHROMIUM (default /opt/pw-browsers/chromium).
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const [worldFile, factsFile, fleetFile, outFile, root, label] = process.argv.slice(2);
const world = JSON.parse(fs.readFileSync(worldFile, 'utf8'));
const facts = JSON.parse(fs.readFileSync(factsFile, 'utf8'));
facts.version = label || '?';
// the sandbox's van: the ZDC Sprinter's parts model (tools/vehicle-preview's export), its nose to -Z, its wheels on y 0
const sprinter = JSON.parse(fs.readFileSync(fleetFile, 'utf8')).find(m => m.id === 'sprinter' && !m.upgraded);
const van = sprinter.parts
  .filter(p => ['Part', 'WedgePart', 'CornerWedgePart'].includes(p.class) && p.opacity > 0.05)
  .map(p => ({
    name: p.name, group: 'Van', class: p.class, mesh: '',
    shape: p.shape === 'Cylinder' || p.shape === 'Ball' ? p.shape : p.class === 'WedgePart' ? 'Wedge' : 'Block',
    p: p.position, r: p.rotation, s: p.size, c: p.color.map(v => Math.round(v * 255)), t: 1 - p.opacity, mat: p.material,
  }));

const TYPES = { '.js': 'text/javascript', '.html': 'text/html', '.woff2': 'font/woff2' };
const server = http.createServer((req, res) => {
  const file = path.join(root, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  if (!file.startsWith(root) || !fs.existsSync(file)) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream' });
  fs.createReadStream(file).pipe(res);
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM || '/opt/pw-browsers/chromium',
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
});
const page = await browser.newPage({ viewport: { width: 2400, height: 1600 } });
page.on('pageerror', e => console.log('page error:', e.message));
await page.goto(`http://127.0.0.1:${server.address().port}/render.html`);
await page.waitForFunction(() => window.ready === true && typeof window.compose === 'function');
const info = await page.evaluate(d => window.compose(d), { world, van, facts });
await page.setViewportSize({ width: info.W, height: info.H });
await page.locator('#sheet').screenshot({ path: outFile });
console.log(`map: ${info.W} x ${info.H}, ${info.parts} parts (the close-up ${info.closeParts}) -> ${outFile}`);
await browser.close();
server.close();
