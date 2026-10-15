// 8.9: renders tools/village's shots (render.html, three.js) in headless Chromium, one PNG a shot.
// Usage (preview.py runs it): node render.mjs <site dir with render.html and three.module.min.js> <shots.json> <out dir>
// Playwright from NODE_PATH (e.g. /opt/node22/lib/node_modules), Chromium from CHROMIUM (default /opt/pw-browsers/chromium).
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const [root, shotsFile, outDir] = process.argv.slice(2);
const shots = JSON.parse(fs.readFileSync(shotsFile, 'utf8'));

const TYPES = { '.js': 'text/javascript', '.html': 'text/html' };
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
try {
  const page = await browser.newPage({ viewport: { width: 1920, height: 1200 } });
  page.on('pageerror', e => console.log('page error:', e.message));
  await page.goto(`http://127.0.0.1:${server.address().port}/render.html`);
  await page.waitForFunction(() => window.ready === true);
  fs.mkdirSync(outDir, { recursive: true });
  for (const shot of shots) {
    const url = await page.evaluate(s => window.renderShot(s), shot);
    const file = path.join(outDir, `${shot.name}.png`);
    fs.writeFileSync(file, Buffer.from(url.split(',')[1], 'base64'));
    console.log(`shot ${shot.name}: ${shot.parts.length} parts -> ${file}`);
  }
} finally {
  await browser.close();
  server.close();
}
