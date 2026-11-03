// Launcher policy, using the production JS/CSS in Chrome with a deterministic clock.
// The fixture supplies Shiny's documented events; it does not run R or replace the
// launcher's policy. Full webR computation remains covered by smoke.mjs.
// CHROME_PATH=/path/to/chrome node .github/pages/smoke/launch-policy.test.mjs [built_site]
// With built_site, verify all generated launcher timings and use them in the fixture.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer-core';

const repo = fileURLToPath(new URL('../../..', import.meta.url));
const evidence = process.env.QA_OUTPUT_DIR && path.resolve(process.env.QA_OUTPUT_DIR);
if (evidence) fs.mkdirSync(evidence, { recursive: true });
const methods = JSON.parse(fs.readFileSync(path.join(repo, 'apps/methods/launch.json')));
const ordinary = JSON.parse(fs.readFileSync(path.join(repo, 'apps/trialmon/launch.json')));
assert.equal(methods.busy_timeout_s, 900, 'methods has a bounded fifteen-minute compute allowance');
assert.equal(ordinary.busy_timeout_s, undefined, 'ordinary apps retain the default policy');
const chrome = process.env.CHROME_PATH;
assert(chrome && fs.existsSync(chrome), 'Set CHROME_PATH to a Chrome binary');
const builtSite = process.argv[2] && path.resolve(process.argv[2]);
const timingFields = ['timeout_s', 'timeout_started_s', 'compute_timeout_s', 'busy_timeout_s'];
const generatedTimings = {};

function verifyBuiltConfigs() {
  const names = fs.readdirSync(path.join(repo, 'apps'))
    .filter(name => fs.existsSync(path.join(repo, 'apps', name, 'launch.json'))).sort();
  assert.deepEqual(names, ['hours', 'lifecycle_dashboard', 'methods', 'risk', 'trialmon', 'uat_irt', 'vaccine'], 'verify every published Shiny app');
  for (const name of names) {
    const html = fs.readFileSync(path.join(builtSite, 'apps', name, 'index.html'), 'utf8');
    const scripts = [...html.matchAll(/<script\b(?=[^>]*\bid=["']launch-config["'])[^>]*>([\s\S]*?)<\/script>/g)];
    assert.equal(scripts.length, 1, `${name}: exactly one generated launch-config`);
    const config = JSON.parse(scripts[0][1]);
    const actual = Object.fromEntries(timingFields.map(key => [key, config[key]]));
    const expected = { timeout_s: 60, timeout_started_s: 120, compute_timeout_s: 45, busy_timeout_s: name === 'methods' ? 900 : 45 };
    assert.deepEqual(actual, expected, `${name}: generated launcher timings`);
    generatedTimings[name] = actual;
  }
  report.built_configs_verified = true;
  console.log(`PASS generated launcher timings for all ${names.length} apps`);
}

function fixture(spec) {
  const config = { relPath: '/', ...Object.fromEntries(timingFields.map(key => [key, spec[key]])) };
  return `<!doctype html><html><head><title>Launcher policy fixture</title>
    <link rel="stylesheet" href="/launch.css"></head><body>
    <h1 id="launch-title">Launcher policy fixture</h1>
    <section id="app" class="launch-app">
      <div class="app-bar"><div class="app-status"><span class="status-stage"></span>
        <span class="status-detail"></span><span class="status-clock"></span></div>
        <button data-action="reload">Reload</button><button data-action="full">Full screen</button></div>
      <div id="root"></div><div class="app-cover" data-cover><div class="cover-card">
        <h2 class="cover-title"></h2><ol>${['page','sw','engine','frame','compute','ready'].map(s => `<li data-step="${s}">${s}</li>`).join('')}</ol>
        <div class="cover-problem" hidden><p class="problem-text"></p><p class="problem-said"></p>
          <p class="problem-reasons-head"></p><ul class="problem-reasons"></ul><p class="problem-try"></p>
          <button data-action="dismiss">Keep waiting</button><button data-action="reload">Reload</button><pre class="log"></pre>
        </div></div></div></section>
    <script id="launch-config" type="application/json">${JSON.stringify(config)}</script>
    <script src="/launch.js"></script></body></html>`;
}

const appFrame = `<!doctype html><html><body><div id="result" class="shiny-bound-output"></div>
  <script>
    const mode = new URLSearchParams(location.search).get('mode');
    if (mode === 'ready') document.getElementById('result').textContent = 'Synthetic fixture result';
    else document.documentElement.classList.add('shiny-busy');
    window.jQuery = doc => ({ on(events, handler) { events.split(' ').forEach(name => doc.addEventListener(name, handler)); } });
    window.Shiny = { shinyapp: { isConnected: () => true } };
    window.emitShiny = name => {
      if (name === 'shiny:busy') document.documentElement.classList.add('shiny-busy');
      if (name === 'shiny:idle') document.documentElement.classList.remove('shiny-busy');
      document.dispatchEvent(new Event(name));
    };
  </script></body></html>`;

const loader = `export function runExportedApp() {
  const mode = new URLSearchParams(location.search).get('mode');
  if (mode === 'loader-error') throw new Error('Fixture loader failure');
  window.fixtureWorker = new Worker('fixture-worker.js');
  if (mode === 'engine') return;
  const frame = document.createElement('iframe');
  frame.src = '/app_fixture/?mode=' + mode;
  document.getElementById('root').appendChild(frame);
}`;

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://fixture');
  let content, type = 'text/html';
  if (req.method === 'HEAD') { res.writeHead(200).end(); return; }
  if (url.pathname === '/') {
    const app = url.searchParams.get('app') === 'methods' ? 'methods' : 'trialmon';
    content = fixture(generatedTimings[app] || (app === 'methods' ? methods : ordinary));
  }
  else if (url.pathname === '/app_fixture/') content = appFrame;
  else if (url.pathname === '/shinylive/shinylive.js') { content = loader; type = 'text/javascript'; }
  else if (url.pathname === '/launch.js' || url.pathname === '/launch.css') {
    content = fs.readFileSync(path.join(repo, 'apps/_shared', url.pathname.slice(1)));
    type = url.pathname.endsWith('.js') ? 'text/javascript' : 'text/css';
  } else { res.writeHead(404).end(); return; }
  res.writeHead(200, { 'Content-Type': type }); res.end(content);
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const base = `http://127.0.0.1:${server.address().port}`;
let browser;
const passed = [];
const report = { browser: chrome, started: new Date().toISOString(), built_site: builtSite || null,
  built_configs_verified: false, generated_timings: generatedTimings, cases: [], passed: false };
try {
  if (builtSite) verifyBuiltConfigs();
  browser = await puppeteer.launch({ executablePath: chrome, headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  async function run(name, app, mode, test) {
    const page = await browser.newPage(), errors = [];
    page.on('pageerror', error => errors.push(String(error)));
    await page.evaluateOnNewDocument(() => {
      // Run real interval callbacks at chosen clock readings. No policy state is
      // mutated: startup, busy, idle and failures enter through their normal events.
      let milliseconds = 1000;
      const intervals = new Map(); let id = 0;
      Object.defineProperty(performance, 'now', { value: () => milliseconds });
      window.setInterval = callback => { intervals.set(++id, callback); return id; };
      window.clearInterval = key => intervals.delete(key);
      window.advanceLauncher = seconds => {
        milliseconds += seconds * 1000;
        for (const callback of [...intervals.values()]) callback();
      };
      const sw = new EventTarget();
      sw.controller = {}; sw.register = async () => ({ scope: location.origin + '/' });
      Object.defineProperty(navigator, 'serviceWorker', { value: sw });
      window.Worker = class extends EventTarget {};
    });
    try {
      await page.goto(`${base}/?app=${app}&mode=${mode}`, { waitUntil: 'load' });
      await page.waitForFunction(() => window.launchStatus?.events.some(e => e.msg === 'runExportedApp started') || window.launchStatus?.problem);
      if (mode === 'ready' || mode === 'compute') {
        await page.waitForFunction(() => window.launchStatus?.connected);
        await page.evaluate(() => window.advanceLauncher(0));
      }
      const advance = seconds => page.evaluate(s => window.advanceLauncher(s), seconds);
      const emit = name => page.frames().find(f => f.url().includes('/app_fixture/')).evaluate(n => window.emitShiny(n), name);
      const state = () => page.evaluate(() => ({
        ...window.launchStatus,
        tone: document.querySelector('.app-status').dataset.tone,
        cover: getComputedStyle(document.querySelector('[data-cover]')).display,
        problemHidden: document.querySelector('.cover-problem').hidden,
        title: document.querySelector('.status-stage').textContent,
        problemText: document.querySelector('.problem-text').textContent,
        keepWaiting: !document.querySelector('[data-action="dismiss"]').hidden
      }));
      await test({ page, advance, emit, state });
      assert.deepEqual(errors, [], 'fixture did not cause an uncaught browser exception');
      passed.push(name); report.cases.push({ name, passed: true }); console.log(`PASS ${name}`);
    } catch (error) {
      report.cases.push({ name, passed: false, error: error.stack || String(error), launch: await page.evaluate(() => window.launchStatus).catch(() => null) });
      if (evidence) await page.screenshot({ path: path.join(evidence, 'failure.png'), fullPage: true }).catch(() => {});
      throw error;
    } finally { await page.close(); }
  }
  for (const [app, limit, checkpoints] of [['methods', 900, [45,300,899]], ['trialmon', 45, [44]]]) {
    await run(`${app}: busy boundary and idle recovery`, app, 'ready', async ({ advance, emit, state }) => {
      assert.equal((await state()).ready, true);
      await emit('shiny:busy');
      let elapsed = 0;
      for (const seconds of checkpoints) {
        await advance(seconds - elapsed); elapsed = seconds;
        const s = await state();
        assert.equal(s.problem, null, `${app}: no warning at ${seconds}s`);
        assert.equal(s.busy, true); assert.equal(s.title, 'Working');
        assert.equal(s.tone, 'progress'); assert.equal(s.cover, 'none');
      }
      await advance(limit - elapsed);
      const overdue = await state();
      assert.equal(overdue.problem, 'busy-long'); assert.equal(overdue.tone, 'warn');
      assert.equal(overdue.cover, 'flex'); assert.equal(overdue.problemHidden, false);
      assert.equal(overdue.keepWaiting, true); assert.match(overdue.problemText, new RegExp(`${limit} seconds`));
      await emit('shiny:idle');
      const idle = await state();
      assert.equal(idle.problem, null); assert.equal(idle.busy, false);
      assert.equal(idle.tone, 'ok'); assert.equal(idle.cover, 'none'); assert.equal(idle.problemHidden, true);
      // A subsequent job receives a fresh allowance, rather than inheriting elapsed time.
      await emit('shiny:busy'); await advance(limit - 1); assert.equal((await state()).problem, null);
      await advance(1); assert.equal((await state()).problem, 'busy-long');
      await emit('shiny:idle'); assert.equal((await state()).problem, null);
    });
  }
  for (const started of [false, true]) {
    await run(`methods: startup ${started ? 120 : 60}s unchanged`, 'methods', 'engine', async ({ page, advance, state }) => {
      if (started) await page.evaluate(() => fixtureWorker.dispatchEvent(new MessageEvent('message', { data: { type: 'stdout', data: 'R version fixture' } })));
      const limit = started ? 120 : 60;
      await advance(limit - 1); assert.equal((await state()).problem, null);
      await advance(1); assert.equal((await state()).problem, 'slow');
      assert.match((await state()).title, new RegExp(`${limit} seconds`));
    });
  }
  await run('methods: first-results 45s unchanged', 'methods', 'compute', async ({ advance, state }) => {
    await advance(44); assert.equal((await state()).problem, null);
    await advance(1); assert.equal((await state()).problem, 'stalled-compute');
  });
  await run('methods: immediate loader failure', 'methods', 'loader-error', async ({ state }) => {
    assert.equal((await state()).problem, 'loader');
  });
  for (const mode of ['engine', 'ready']) {
    await run(`methods: immediate worker failure while ${mode}`, 'methods', mode, async ({ page, state }) => {
      await page.evaluate(() => fixtureWorker.dispatchEvent(new ErrorEvent('error', { message: 'Fixture worker failure' })));
      assert.equal((await state()).problem, mode === 'ready' ? 'disconnected' : 'engine-died');
    });
  }
  await run('methods: immediate Shiny disconnection', 'methods', 'ready', async ({ emit, state }) => {
    await emit('shiny:busy'); await emit('shiny:disconnected');
    assert.equal((await state()).problem, 'disconnected');
  });
  await run('methods: stack failure remains fatal during work and after idle', 'methods', 'ready', async ({ page, emit, state }) => {
    await emit('shiny:busy');
    await page.evaluate(() => window.dispatchEvent(new ErrorEvent('error', { message: 'Maximum call stack size exceeded' })));
    assert.equal((await state()).problem, 'stack'); assert.equal((await state()).tone, 'error');
    await emit('shiny:idle'); assert.equal((await state()).problem, 'stack');
  });
  report.passed = true;
  console.log(JSON.stringify({ passed: passed.length, built_configs_verified: report.built_configs_verified, cases: passed }, null, 2));
} catch (error) {
  report.error = error.stack || String(error);
  throw error;
} finally {
  report.finished = new Date().toISOString();
  if (evidence) fs.writeFileSync(path.join(evidence, 'report.json'), JSON.stringify(report, null, 2) + '\n');
  if (browser) await browser.close();
  await new Promise(resolve => server.close(resolve));
}
