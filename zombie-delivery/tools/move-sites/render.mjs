// 7.0: renders check.py's export (the moves' world and its context) with three.js in headless Chromium, one PNG a view.
// Usage (render.py runs it): node render.mjs <scene.json> <views.json> <out dir> <dir with render.html and three.module.min.js>
// Playwright from NODE_PATH (e.g. /opt/node22/lib/node_modules), Chromium from CHROMIUM (default /opt/pw-browsers/chromium).
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const [sceneFile, viewsFile, outDir, root] = process.argv.slice(2);
const records = JSON.parse(fs.readFileSync(sceneFile, 'utf8'));
const views = JSON.parse(fs.readFileSync(viewsFile, 'utf8'));
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
const page = await browser.newPage({ viewport: { width: 1400, height: 900 } });
page.on('pageerror', e => console.log('page error:', e.message));
await page.goto(`http://127.0.0.1:${server.address().port}/render.html`);
await page.waitForFunction(() => window.ready === true);
await page.evaluate(r => window.loadScene(r), records);
for (const view of views) {
  await page.setViewportSize({ width: view.size[0], height: view.size[1] });
  await page.evaluate(v => window.renderView(v), view);
  await page.locator('canvas').screenshot({ path: path.join(outDir, `${view.name}.png`) });
}
console.log('rendered', views.length, 'views of', records.length, 'records');
await browser.close();
server.close();
