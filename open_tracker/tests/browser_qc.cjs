/* Reproducible Chromium QC using only synthetic temporary data.
 * Install Playwright separately, then:
 *   NODE_PATH=/path/to/node_modules TRACKER_PYTHON=/path/to/shared-venv/bin/python \
 *   CHROME_PATH=/path/to/chrome node open_tracker/tests/browser_qc.cjs
 * CHROME_PATH is optional when Playwright's Chromium is installed.
 * QA_OUTPUT_DIR optionally selects retained screenshots/report. No emails are sent.
 */
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const cp = require('node:child_process');
const crypto = require('node:crypto');
const { once } = require('node:events');
const root = path.resolve(__dirname, '../..');
const python = process.env.TRACKER_PYTHON || 'python3';
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'tracker-browser-fixtures-'));
const output = process.env.QA_OUTPUT_DIR || fs.mkdtempSync(path.join(os.tmpdir(), 'tracker-browser-evidence-'));
fs.mkdirSync(output, { recursive: true });
const template = fs.readFileSync(path.join(root, 'open_tracker/index.html'), 'utf8');
const marker = /(<script\b[^>]*\bid="tracker-data"[^>]*>)[\s\S]*?(<\/script\s*>)/i;
const seed = JSON.parse(template.match(/<script id="tracker-data" type="application\/json">([\s\S]*?)<\/script>/)[1]);
const fixturePage = data => template.replace(marker, (_, a, b) => a + JSON.stringify(data).replaceAll('<', '\\u003c') + b);
const fixtures = new Map();
const report = { started_at: new Date().toISOString(), scenarios: [], errors: [], screenshots: [], limitations: ['Chromium only; synthetic data; no external email delivery or clinical-method validation.'] };
let browser, serverProcess, staticServer;
const errors = [], requests = [];
const password = 'Synthetic-' + crypto.randomBytes(18).toString('hex');
const db = path.join(temp, 'shared.sqlite');
function runPython(code, args = []) { return cp.execFileSync(python, ['-c', code, root, ...args], { encoding: 'utf8', env: { ...process.env, TRACKER_QA_PASSWORD: password }, maxBuffer: 20 * 1024 * 1024 }); }
function changed(data, fn) { const result = structuredClone(data); fn(result); return result; }
async function scenario(name, fn) { await fn(); report.scenarios.push({ name, passed: true }); console.log('PASS ' + name); }
async function importJSON(page, data, raw = false) {
  await page.evaluate(() => { document.getElementById('message').textContent = ''; });
  await page.locator('#import-file').setInputFiles({ name: 'synthetic.json', mimeType: 'application/json', buffer: Buffer.from(raw ? data : JSON.stringify(data)) });
  await page.waitForFunction(() => document.getElementById('message').textContent.length > 0);
}
async function exported(page, button = '#export-json') { const next = page.waitForEvent('download'); await page.locator(button).click(); return fs.readFileSync(await (await next).path(), 'utf8'); }
async function edit(page, id, field, value) { await page.getByRole('button', { name: `Edit ${id}`, exact: true }).click(); await page.locator('#' + field).fill(value); }
async function save(page) { await page.getByRole('button', { name: 'Save deliverable', exact: true }).click(); }
async function trackPage(context, url, shared = false) {
  const p = await context.newPage(); p.on('pageerror', e => errors.push(e.message)); p.on('request', r => requests.push(r.url())); p.on('dialog', d => d.accept());
  if (shared) await p.addInitScript(() => { const get=Storage.prototype.getItem,set=Storage.prototype.setItem;Storage.prototype.getItem=function(key){if(key==='bp-theme')return get.call(this,key);throw Error('Shared UI read task data from localStorage');};Storage.prototype.setItem=function(key,value){if(key==='bp-theme')return set.call(this,key,value);throw Error('Shared UI saved task data to localStorage');}; });
  await p.goto(url); await p.waitForFunction(() => document.getElementById('save-state').textContent !== 'Loading workspace…'); return p;
}
async function login(page, username = 'editor') { await page.locator('#login-username').fill(username); await page.locator('#login-password').fill(password); await page.locator('#login-submit').click(); await page.locator('#workspace-shell').waitFor({ state: 'visible' }); }
(async () => {
  staticServer = http.createServer((req, res) => { const url = new URL(req.url, 'http://local'); const content = fixtures.get(url.pathname) || template; res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' }); res.end(content); });
  staticServer.listen(0, '127.0.0.1'); await once(staticServer, 'listening'); const base = `http://127.0.0.1:${staticServer.address().port}`;
  const setup = `import os,sys,secrets\nsys.path.insert(0,sys.argv[1])\nfrom open_tracker import server,tracker\nfrom waitress import create_server\ndb=sys.argv[2]\nfor username,role in [('editor','editor'),('viewer','viewer'),('reviewer','editor')]: server.manage_user(db,'add-user',username,os.environ['TRACKER_QA_PASSWORD'],role)\ntracker.upsert(db,tracker.read_input(sys.argv[1]+'/open_tracker/examples/status.csv','csv'),'Synthetic fixture')\napp=server.create_app({'DATABASE':db,'SECRET_KEY':secrets.token_urlsafe(48),'COOKIE_SECURE':False})\ns=create_server(app,host='127.0.0.1',port=0)\nprint('READY '+str(s.effective_port),flush=True)\ns.run()`;
  serverProcess = cp.spawn(python, ['-u', '-c', setup, root, db], { env: { ...process.env, TRACKER_QA_PASSWORD: password }, stdio: ['ignore', 'pipe', 'pipe'] });
  const sharedBase = await new Promise((resolve, reject) => { let text = '', err = ''; const timeout = setTimeout(() => reject(Error('Shared fixture server startup timeout: ' + err)), 30000); serverProcess.stdout.on('data', d => { text += d; const m = text.match(/READY (\d+)/); if (m) { clearTimeout(timeout); resolve('http://127.0.0.1:' + m[1]); } }); serverProcess.stderr.on('data', d => { err += d; }); serverProcess.on('exit', code => { clearTimeout(timeout); reject(Error('Shared fixture server exited: ' + code + ' ' + err)); }); });
  browser = await chromium.launch({ headless: true, ...(process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {}) });
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, acceptDownloads: true });
  const page = await trackPage(context, base + '/open_tracker/index.html');
  await scenario('Portfolio prototype framing, synthetic initial rows and filters', async () => {
    assert.match(await page.locator('#evaluation-note').textContent(), /Portfolio evaluation prototype/);
    assert.equal(await page.locator('#count-all').textContent(), '4');
    await page.locator('#stat-attention').click(); assert.equal(await page.locator('#rows tr').count(), 2);
    await page.locator('#clear-filters').click(); await page.locator('#search').fill('007'); assert.equal(await page.locator('#rows tr').count(), 1); await page.locator('#clear-filters').click();
  });
  await scenario('Keyboard editor, safe text, persistence and literal zero-padded IDs', async () => {
    await page.getByRole('button', { name: 'Edit 007', exact: true }).focus(); await page.keyboard.press('Enter'); assert.equal(await page.locator('#task-id').isDisabled(), true);
    await page.locator('#title').fill('Reviewed transfer'); await page.locator('#owner').fill(''); await page.locator('#notes').fill('</script><script>window.injected=true</script>'); await save(page); await page.reload();
    assert.equal(await page.locator('.task-title').filter({ hasText: 'Reviewed transfer' }).count(), 1); assert.equal(await page.evaluate(() => window.injected), undefined);
    await edit(page, '007', 'notes', 'Cancel with Escape'); await page.keyboard.press('Escape'); assert.equal(await page.locator('#editor').isVisible(), false);
  });
  await scenario('Toolkit light/dark theme changes surfaces and persists independently of task data', async () => {
    const toggle=page.locator('.theme-toggle');await toggle.click();const first=await page.locator('html').getAttribute('data-theme');const background=await page.locator('.workspace').evaluate(e=>getComputedStyle(e).backgroundColor);await page.bringToFront();await page.screenshot({path:path.join(output,'tracker-'+first+'-desktop.png')});report.screenshots.push('tracker-'+first+'-desktop.png');await toggle.click();assert.notEqual(await page.locator('html').getAttribute('data-theme'),first);assert.notEqual(await page.locator('.workspace').evaluate(e=>getComputedStyle(e).backgroundColor),background);const stored=await page.locator('html').getAttribute('data-theme');await page.screenshot({path:path.join(output,'tracker-'+stored+'-desktop.png')});report.screenshots.push('tracker-'+stored+'-desktop.png');await page.reload();assert.equal(await page.locator('html').getAttribute('data-theme'),stored);
  });
  await scenario('Different page paths cannot restore each other’s drafts', async () => {
    const other = await trackPage(context, base + '/different-snapshot.html'); assert.equal(await other.locator('.task-title').filter({ hasText: 'Reviewed transfer' }).count(), 0); await other.close();
  });
  await scenario('Concurrent offline tabs cannot silently overwrite a saved draft', async () => {
    const other = await trackPage(context, base + '/open_tracker/index.html');
    await edit(page, '007', 'title', 'First tab saved'); await save(page);
    await edit(other, '007', 'title', 'Second tab unsaved'); await save(other);
    assert.match(await other.locator('#message').textContent(), /not overwritten/);
    const second = JSON.parse(await exported(other)); assert.equal(second.rows.find(r => r.task_id === '007').title, 'Second tab unsaved');
    await page.reload(); assert.equal(await page.locator('.task-title').filter({ hasText: 'First tab saved' }).count(), 1); await other.close();
  });
  await scenario('Seed verification rejects a foreign draft even at the same storage key', async () => {
    await page.evaluate(() => { const key = Object.keys(localStorage).find(k => k.includes('open_tracker%2Findex.html')); const record = JSON.parse(localStorage.getItem(key)); record.seed = 'different snapshot with matching key'; record.snapshot.rows[0].title = 'FOREIGN DRAFT'; localStorage.setItem(key, JSON.stringify(record)); });
    await page.reload(); assert.match(await page.locator('#message').textContent(), /another snapshot/); assert.equal(await page.locator('.task-title').filter({ hasText: 'FOREIGN DRAFT' }).count(), 0);
    await page.evaluate(() => localStorage.clear()); await page.reload();
  });
  await scenario('JSON export roundtrip clears fields in real SQLite; review CSV neutralizes formulas', async () => {
    await edit(page, '007', 'owner', ''); await page.locator('#title').fill('=1+1'); await page.locator('#notes').fill('\t=SUM(A1)'); await save(page);
    const json = JSON.parse(await exported(page)); const file = path.join(temp, 'browser.json'); fs.writeFileSync(file, JSON.stringify(json));
    const result = JSON.parse(runPython("import sys,json;sys.path.insert(0,sys.argv[1]);from open_tracker import tracker;tracker.upsert(sys.argv[2],tracker.read_input(sys.argv[3],'json'),'browser QC');print(json.dumps(tracker.snapshot(sys.argv[2])))", [path.join(temp, 'roundtrip.sqlite'), file]));
    assert.equal(result.rows.find(r => r.task_id === '007').owner, ''); assert.equal(result.rows.find(r => r.task_id === '007').task_id, '007');
    const csv = await exported(page, '#export-csv'); assert.match(csv, /'=1\+1/); assert.match(csv, /'\t=SUM/);
  });
  await scenario('Malformed imports are atomic: duplicate IDs/keys, dates, unknown fields and Unicode', async () => {
    const cases = [changed(seed, s => s.rows.push(s.rows[0])), changed(seed, s => { s.rows[0].due = '2026-02-30'; }), changed(seed, s => { s.rows[0].due = '0000-01-01'; }), changed(seed, s => { s.rows[0].extra = true; }), changed(seed, s => { s.rows[0].title = '\ud800'; }), changed(seed, s => { s.exported_at = '2026-02-30T12:00:00Z'; })];
    for (const data of cases) { await importJSON(page, data); assert.match(await page.locator('#message').textContent(), /Import rejected/); assert.equal(await page.locator('#count-all').textContent(), '4'); }
    const duplicate = JSON.stringify(seed).replace('"schema_version":1', '"schema_version":1,"schema_\\u0076ersion":1'); await importJSON(page, duplicate, true); assert.match(await page.locator('#message').textContent(), /Duplicate JSON property/);
    const proto = JSON.stringify(seed).replace('"schema_version":1', '"schema_version":1,"__proto__":{"polluted":true}'); await importJSON(page, proto, true); assert.equal(await page.evaluate(() => ({}).polluted), undefined); assert.match(await page.locator('#message').textContent(), /Import rejected/);
  });
  await scenario('Valid Unicode remains valid at code-point limits and survives backend import', async () => {
    const unicode = changed(seed, s => { s.rows[0].title = '🧪'.repeat(160); }); await importJSON(page, unicode); assert.equal(await page.locator('.task-title').first().textContent(), '🧪'.repeat(160));
    await edit(page, 'DEMO-ADAM', 'owner', 'QC 🧪'); await save(page); const file = path.join(temp, 'unicode.json'); fs.writeFileSync(file, await exported(page)); runPython("import sys;sys.path.insert(0,sys.argv[1]);from open_tracker import tracker;tracker.upsert(sys.argv[2],tracker.read_input(sys.argv[3],'json'),'unicode QC')", [path.join(temp, 'unicode.sqlite'), file]);
  });
  await scenario('Large histories render only recent12 without the former50,000-event lockout', async () => {
    const large = changed(seed, s => { s.events = Array.from({ length: 50001 }, (_, i) => ({ id: i + 1, task_id: '007', changed_at: '2026-10-28T12:00:00Z', actor: 'Synthetic QC', changes: {} })); });
    fixtures.set('/large.html', fixturePage(large)); const p = await trackPage(context, base + '/large.html'); await p.waitForFunction(() => document.querySelectorAll('#history li').length === 12); assert.equal(await p.locator('#count-all').textContent(), '4'); await edit(p, '007', 'progress', '26'); await save(p); assert.equal(await p.locator('#editor').isVisible(), false); await p.close();
  });
  await scenario('Oversized files fail before replacing the current workspace', async () => {
    const largeText = ' '.repeat(5 * 1024 * 1024 + 1); await importJSON(page, largeText, true); assert.match(await page.locator('#message').textContent(), /File is too large/); assert.equal(await page.locator('#count-all').textContent(), '4');
  });
  await scenario('Unavailable browser storage keeps an exportable tab draft', async () => {
    const c = await browser.newContext(); const p = await c.newPage(); await p.addInitScript(() => { Storage.prototype.setItem = () => { throw new DOMException('Quota', 'QuotaExceededError'); }; }); await p.goto(base); await edit(p, '007', 'progress', '30'); await save(p); assert.match(await p.locator('#message').textContent(), /held in this tab only/); assert.equal(JSON.parse(await exported(p)).rows.find(r => r.task_id === '007').progress, 30); await c.close();
  });
  await scenario('Offline file URL, mobile layout and keyboard skip link', async () => {
    const p = await context.newPage(); await p.goto('file://' + path.join(root, 'open_tracker/index.html')); assert.equal(await p.locator('#count-all').textContent(), '4'); await p.close();
    await page.setViewportSize({ width: 390, height: 844 }); assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false); await page.bringToFront(); await page.waitForTimeout(100); await page.screenshot({ path: path.join(output, 'tracker-mobile.png') }); report.screenshots.push('tracker-mobile.png');
    await page.locator('.skip').focus(); await page.keyboard.press('Enter'); assert.equal(await page.evaluate(() => document.activeElement.id), 'main');
  });
  const editor = await trackPage(await browser.newContext({ viewport: { width: 1440, height: 1000 } }), sharedBase, true);
  const viewer = await trackPage(await browser.newContext(), sharedBase, true);
  const reviewer = await trackPage(await browser.newContext(), sharedBase, true);
  await scenario('Shared anonymous state, failed/successful login and no browser storage', async () => {
    assert.equal(await editor.locator('#workspace-shell').isVisible(), false); assert.equal(await editor.locator('#rows').textContent(), '');
    await editor.locator('#login-username').fill('editor'); await editor.locator('#login-password').fill('incorrect'); await editor.locator('#login-submit').click(); await editor.waitForFunction(() => document.getElementById('login-error').textContent.includes('Invalid')); await login(editor); assert.equal(await editor.locator('#login-password').inputValue(), ''); assert.match(await editor.locator('#evaluation-note').textContent(), /Portfolio evaluation/);
  });
  await scenario('Viewer controls and server-side write rejection', async () => {
    await login(viewer, 'viewer'); assert.equal(await viewer.locator('.edit-btn').count(), 0); assert.equal(await viewer.locator('#add-row').isVisible(), false);
    const status = await viewer.evaluate(async () => { const s = await (await fetch('/api/session')).json(), data = await (await fetch('/api/snapshot')).json(); return (await fetch('/api/tasks', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': s.csrf_token }, body: JSON.stringify({ row: data.rows[0], expected_updated_at: data.rows[0].updated_at }) })).status; }); assert.equal(status, 403);
  });
  await scenario('Independent editor conflict preserves the unsaved typed draft', async () => {
    await login(reviewer, 'reviewer'); await edit(editor, '007', 'notes', 'Keep this conflict draft'); await edit(reviewer, '007', 'progress', '80'); await save(reviewer); await reviewer.locator('#editor').waitFor({ state: 'hidden' }); await save(editor); await editor.waitForFunction(() => document.getElementById('edit-error').textContent.includes('changed after')); assert.equal(await editor.locator('#notes').inputValue(), 'Keep this conflict draft'); await editor.locator('#cancel-edit').click(); await editor.locator('#refresh-shared').click(); await editor.waitForFunction(() => document.getElementById('rows').textContent.includes('80%'));
  });
  await scenario('Network and unreadable server failures preserve drafts; retry saves', async () => {
    await edit(editor, '007', 'notes', 'Survive a network failure'); await editor.route('**/api/tasks', r => r.abort()); await save(editor); await editor.waitForFunction(() => document.getElementById('edit-error').textContent.length > 0); assert.equal(await editor.locator('#notes').inputValue(), 'Survive a network failure'); await editor.unroute('**/api/tasks');
    await editor.route('**/api/tasks', r => r.fulfill({ status: 502, contentType: 'text/html', body: '<h1>Unavailable</h1>' })); await save(editor); await editor.waitForFunction(() => document.getElementById('edit-error').textContent.includes('unreadable')); await editor.unroute('**/api/tasks'); await save(editor); await editor.locator('#editor').waitFor({ state: 'hidden' });
  });
  await scenario('In-flight save cannot close and discard a newer editor draft', async () => {
    let release; const gate = new Promise(r => { release = r; }); let arrived; const started = new Promise(r => { arrived = r; });
    await editor.route('**/api/tasks', async r => { const response = await r.fetch(); arrived(); await gate; await r.fulfill({ response }); });
    await edit(editor, '007', 'progress', '81'); await save(editor); await started; assert.equal(await editor.locator('#cancel-edit').isDisabled(), true); await editor.keyboard.press('Escape'); assert.equal(await editor.locator('#editor').isVisible(), true); release(); await editor.locator('#editor').waitFor({ state: 'hidden' }); await editor.unroute('**/api/tasks');
  });
  await scenario('Delayed refresh cannot restore data or hide login after sign-out', async () => {
    let release; const gate = new Promise(r => { release = r; }); let arrived; const started = new Promise(r => { arrived = r; });
    await editor.route('**/api/snapshot', async r => { const response = await r.fetch(); arrived(); await gate; await r.fulfill({ response }); });
    await editor.locator('#refresh-shared').click(); await started; await editor.locator('#logout').click(); await editor.locator('#login-panel').waitFor({ state: 'visible' }); release(); await editor.waitForTimeout(200); assert.equal(await editor.locator('#workspace-shell').isVisible(), false); assert.equal(await editor.locator('#rows').textContent(), ''); assert.equal(await editor.locator('#history').textContent(), ''); await editor.unroute('**/api/snapshot');
  });
  await scenario('Expired cookie and disabled accounts clear all loaded data', async () => {
    await login(editor); await edit(editor, '007', 'notes', 'Expired session draft'); await editor.context().clearCookies(); await save(editor); await editor.locator('#login-panel').waitFor({ state: 'visible' }); assert.equal(await editor.locator('#rows').textContent(), '');
    runPython("import sys;sys.path.insert(0,sys.argv[1]);from open_tracker import server;server.manage_user(sys.argv[2],'disable-user','reviewer')", [db]); await reviewer.locator('#refresh-shared').click(); await reviewer.locator('#login-panel').waitFor({ state: 'visible' }); assert.equal(await reviewer.locator('#history').textContent(), '');
  });
  await scenario('Shared mobile layout and final runtime/network isolation', async () => {
    await login(editor); await editor.locator('.theme-toggle').click(); assert.ok(['light','dark'].includes(await editor.locator('html').getAttribute('data-theme'))); await editor.screenshot({ path: path.join(output, 'tracker-shared-desktop.png'), fullPage: true }); report.screenshots.push('tracker-shared-desktop.png'); await editor.setViewportSize({ width: 390, height: 844 }); assert.equal(await editor.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
    assert.deepEqual(errors, []); assert.ok(requests.every(url => url.startsWith(base + '/') || url.startsWith(sharedBase + '/')));
  });
  report.passed = true;
})().catch(error => { report.passed = false; report.errors.push(error.stack); console.error(error); process.exitCode = 1; }).finally(async () => {
  if (browser) await browser.close(); if (serverProcess) serverProcess.kill('SIGTERM'); if (staticServer) await new Promise(r => staticServer.close(r));
  report.completed_at = new Date().toISOString(); report.scenario_count = report.scenarios.length; report.uncaught_browser_errors = errors; fs.writeFileSync(path.join(output, 'browser-qc-report.json'), JSON.stringify(report, null, 2)); fs.rmSync(temp, { recursive: true, force: true }); console.log(`Evidence: ${output}; ${report.scenarios.length} scenarios passed.`);
});
