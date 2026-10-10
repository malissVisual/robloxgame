// 6.22: renders export.luau's JSON lines (one inventory thing each) with three.js in headless Chromium, one PNG a
// thing. Usage (render.py runs it): node render.mjs <scenes.jsonl> <out dir> <dir with render.html and three.module.min.js>
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
const page = await browser.newPage({ viewport: { width: 320, height: 320 } });
page.on('pageerror', e => console.log('page error:', e.message));
await page.goto(`http://127.0.0.1:${server.address().port}/render.html`);
await page.waitForFunction(() => window.ready === true);
const labels = {};
for (const scene of scenes) {
  await page.evaluate(s => window.renderScene(s), scene);
  await page.locator('canvas').screenshot({ path: path.join(outDir, `${scene.name}.png`) });
  labels[scene.name] = { label: scene.info.label, key: scene.info.key, parts: scene.info.parts };
}
fs.writeFileSync(path.join(outDir, 'labels.json'), JSON.stringify(labels, null, 1));
console.log('rendered', scenes.length);
await browser.close();
server.close();
