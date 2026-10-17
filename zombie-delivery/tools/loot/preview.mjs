// 9.x loot: renders preview.py's data with preview.html (three.js) in headless Chromium and saves the picture.
// Usage (preview.py runs it): node preview.mjs <site dir with preview.html, three.module.min.js, the fonts> <data.json> <out.png>
// Playwright from NODE_PATH (e.g. /opt/node22/lib/node_modules), Chromium from CHROMIUM (default /opt/pw-browsers/chromium).
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const [root, dataFile, outFile] = process.argv.slice(2);
const data = JSON.parse(fs.readFileSync(dataFile, 'utf8'));
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
const page = await browser.newPage({ viewport: { width: 1800, height: 1040 } });
page.on('pageerror', e => console.log('page error:', e.message));
page.on('console', m => { if (m.type() === 'error') console.log('console:', m.text()); });
await page.goto(`http://127.0.0.1:${server.address().port}/preview.html`);
await page.waitForFunction(() => window.ready === true);
await page.evaluate(() => document.fonts.load('700 20px Gotham').then(() => document.fonts.load('500 20px Gotham')));
await page.evaluate(d => window.renderLoot(d), data);
fs.mkdirSync(path.dirname(outFile), { recursive: true });
await page.locator('#out').screenshot({ path: outFile });
console.log('rendered', outFile);
await browser.close();
server.close();
