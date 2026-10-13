// 7.1, the Alps: renders view.html (a 3/4 view of the layout's stretch) in headless Chromium to a PNG.
// Usage (render.py runs it): node view.mjs <dir with view.html, three.module.min.js and scene.json> <out.png>
// Playwright from NODE_PATH (e.g. /opt/node22/lib/node_modules), Chromium from CHROMIUM (default /opt/pw-browsers/chromium).
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const [root, out] = process.argv.slice(2);

const server = http.createServer((req, res) => {
  const file = path.join(root, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  if (!file.startsWith(root) || !fs.existsSync(file)) { res.writeHead(404); res.end(); return; }
  const type = file.endsWith('.js') ? 'text/javascript' : file.endsWith('.json') ? 'application/json' : 'text/html';
  res.writeHead(200, { 'Content-Type': type });
  fs.createReadStream(file).pipe(res);
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM || '/opt/pw-browsers/chromium',
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
});
try {
  const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
  page.on('pageerror', e => console.log('page error:', e.message));
  page.on('console', m => console.log('page:', m.text()));
  await page.goto(`http://127.0.0.1:${server.address().port}/view.html`);
  await page.waitForFunction(() => window.ready === true, null, { timeout: 600000 });
  await page.screenshot({ path: out });
  console.log(`wrote ${out}`);
} finally {
  await browser.close();
  server.close();
}
