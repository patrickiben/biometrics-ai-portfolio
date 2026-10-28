/* Whole-site runtime and navigation QC. No runtime dependency is added to the site.
 * NODE_PATH=/path/to/playwright/node_modules CHROME_PATH=/path/to/chrome \
 *   node .github/pages/smoke/site_qc.cjs [repository-root]
 * QA_OUTPUT_DIR selects retained JSON evidence and screenshots.
 * Published Shinylive apps use the separate smoke.mjs --base-url workflow.
 */
const { chromium } = require('playwright');
const fs = require('node:fs'), path = require('node:path'), os = require('node:os'), http = require('node:http');
const assert = require('node:assert/strict');
const root = path.resolve(process.argv[2] || path.join(__dirname, '../../..'));
const output = process.env.QA_OUTPUT_DIR || fs.mkdtempSync(path.join(os.tmpdir(), 'portfolio-site-qc-'));
fs.mkdirSync(output, { recursive: true });
const prefix = '/biometrics-ai-portfolio/';
const skip = new Set(['.git', 'node_modules', '.quarto', '_site', 'site_libs', '_partials']);
const pages = [];
function walk(dir) { for (const entry of fs.readdirSync(dir, { withFileTypes: true })) { const file = path.join(dir, entry.name), rel = path.relative(root, file).split(path.sep).join('/'); if (entry.isDirectory() && !skip.has(entry.name)) walk(file); else if (entry.isFile() && entry.name.endsWith('.html') && !entry.name.startsWith('_') && !rel.startsWith('apps/_shared/')) pages.push(rel); } }
walk(root); pages.sort();
if(process.env.SITE_QC_MODE === "interactions") pages.length = 0;
if(process.env.SITE_QC_PAGES){const selected=new Set(process.env.SITE_QC_PAGES.split(','));for(let i=pages.length-1;i>=0;i--)if(!selected.has(pages[i]))pages.splice(i,1);}
const mime = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.webp': 'image/webp', '.woff2': 'font/woff2', '.pdf': 'application/pdf', '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' };
const server = http.createServer((req, res) => { let file; try { const u = new URL(req.url, 'http://local'); if (!u.pathname.startsWith(prefix)) { res.writeHead(404); return res.end(); } file = path.resolve(root, '.' + decodeURIComponent(u.pathname.slice(prefix.length - 1))); if (!file.startsWith(root + path.sep) && file !== root) { res.writeHead(403); return res.end(); } if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, 'index.html'); if (!fs.existsSync(file)) { res.writeHead(404); return res.end(); } res.writeHead(200, { 'Content-Type': mime[path.extname(file)] || 'application/octet-stream' }); fs.createReadStream(file).pipe(res); } catch { res.writeHead(500); res.end(); } });
const report = { started_at: new Date().toISOString(), pages: [], interactions: [], failures: [], limitations: ['Local source copies of the three Shinylive launch pages are documented placeholders; deployed apps are checked separately.', 'Page loading and UI interactions do not certify numerical methods or regulatory suitability.'] };
let browser;
(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve)); const base = `http://127.0.0.1:${server.address().port}${prefix}`;
  browser = await chromium.launch({ headless: true, ...(process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {}) });
  const hubs = new Set(['index.html', 'Operations.html', 'Biostatistics.html', 'START_HERE.html', 'GET_STARTED.html']);
  const visualPages = new Set([...hubs, 'open_tracker/index.html', 'open_tracker/SETUP.html', 'sasr_onleave_wiki/Continuity_Toolkit.html', 'lifecycle_dashboard/Study_Lifecycle_Monitor.html', 'sas_tlf_pseudocode/index.html', 'tlf_interpret/index.html', 'uat_irt/quarto/uat-guide.html', 'uat_irt/quarto/uat-slides.html', 'study/04_analysis/report/report.html']);
  let next = 0;
  async function worker() {
    const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, acceptDownloads: true });
    await context.route('**/*', route => route.request().url().startsWith(base) || !/^https?:/.test(route.request().url()) ? route.continue() : route.abort());
    const page = await context.newPage(); let result;
    page.on('pageerror', error => result?.runtime_errors.push(error.message));
    page.on('response', response => { if (response.status() >= 400) result?.http_errors.push({ url: response.url(), status: response.status() }); });
    page.on('request', request => { if (/^https?:/.test(request.url()) && !request.url().startsWith(base)) result?.external_dependencies.push(request.url()); });
    while (next < pages.length) {
      const file = pages[next++]; result = { file, runtime_errors: [], http_errors: [], external_dependencies: [] };
      try {
        await page.setViewportSize({ width: 1440, height: 900 }); await page.goto(base + file, { waitUntil: 'load', timeout: 20000 }); await page.waitForTimeout(150);
        const dom = await page.evaluate(() => ({ title: document.title, text_length: document.body.innerText.trim().length, links: [...document.querySelectorAll('a[href]')].map(a => a.getAttribute('href')), missing_anchors: [...document.querySelectorAll('a[href^="#"]')].map(a => a.getAttribute('href').slice(1)).filter(id => id && !id.startsWith('/') && !document.getElementById(decodeURIComponent(id)) && !document.getElementsByName(decodeURIComponent(id)).length), desktop_overflow: document.documentElement.scrollWidth > innerWidth + 2 }));
        Object.assign(result, { title: dom.title, text_length: dom.text_length, missing_anchors: [...new Set(dom.missing_anchors)], desktop_overflow: dom.desktop_overflow });
        result.theme = { toggle_count: await page.locator('.theme-toggle').count() };
        if(result.theme.toggle_count){
          const button=page.locator('.theme-toggle').first();
          const signature=()=>page.evaluate(()=>({theme:document.documentElement.dataset.theme||getComputedStyle(document.documentElement).colorScheme,colors:[document.body,...document.querySelectorAll('.top,.card,.panel,main,table')].slice(0,15).map(e=>[getComputedStyle(e).color,getComputedStyle(e).backgroundColor])}));
          const contrast=()=>page.evaluate(()=>{
            const rgb=s=>{const m=s.match(/[\d.]+/g);return m&&m.slice(0,3).map(Number)};
            const lum=c=>c.map(x=>{x/=255;return x<=.04045?x/12.92:((x+.055)/1.055)**2.4}).reduce((v,x,i)=>v+x*[.2126,.7152,.0722][i],0);
            const failures=[];let checked=0;
            for(const e of document.querySelectorAll('h1,h2,h3,.callout p,.callout strong,.mc-top b,.note,.warn,.scen label.opt,.checklist li,#heat .cell,#trend .legend span')){
              const s=getComputedStyle(e),r=e.getBoundingClientRect();if(!e.textContent.trim()||!r.width||!r.height||s.visibility==='hidden')continue;
              let ancestor=e;const layers=[];
              while(ancestor){const values=getComputedStyle(ancestor).backgroundColor.match(/[\d.]+/g);if(values)layers.push(values.map(Number));ancestor=ancestor.parentElement;}
              const bg=layers.reverse().reduce((base,c)=>base.map((x,i)=>c[i]*(c[3]??1)+x*(1-(c[3]??1))),[255,255,255]);
              const fg=rgb(s.color);if(!fg)continue;
              const levels=[lum(fg),lum(bg)].sort((a,b)=>a-b),ratio=(levels[1]+.05)/(levels[0]+.05),large=parseFloat(s.fontSize)>=24||(parseFloat(s.fontSize)>=18.66&&Number(s.fontWeight)>=700),minimum=large?3:4.5;
              checked++;if(ratio+.02<minimum)failures.push({text:e.textContent.trim().slice(0,90),ratio:+ratio.toFixed(2),minimum,color:s.color,background:bg});
            }
            return{theme:document.documentElement.dataset.theme,checked,failures};
          });
          const initial=await signature();result.theme.contrast={initial:await contrast()};await button.click();await page.waitForTimeout(60);const flipped=await signature();result.theme.contrast.flipped=await contrast();
          result.theme.changed=initial.theme!==flipped.theme&&JSON.stringify(initial.colors)!==JSON.stringify(flipped.colors);
          await page.reload({waitUntil:'load',timeout:20000});result.theme.persisted=(await signature()).theme===flipped.theme;
          await page.locator('.theme-toggle').first().click();await page.waitForTimeout(50);result.theme.returned=(await signature()).theme===initial.theme;
        }
        result.broken_local_links = [];
        for (const link of dom.links) { if (!link || /^(?:https?:|mailto:|tel:|javascript:|data:|#)/i.test(link)) continue; const u = new URL(link, base + file); if (!u.pathname.startsWith(prefix)) continue; let target = path.join(root, decodeURIComponent(u.pathname.slice(prefix.length))); if (fs.existsSync(target) && fs.statSync(target).isDirectory()) target = path.join(target, 'index.html'); if (!fs.existsSync(target)) result.broken_local_links.push(link); }
        if (hubs.has(file)) { await page.bringToFront(); await page.evaluate(()=>scrollTo(0,0)); await page.screenshot({ path: path.join(output, file.replace('.html', '') + '-desktop.png') }); }
        await page.setViewportSize({ width: 390, height: 844 }); await page.waitForTimeout(100);
        result.mobile_overflow = await page.evaluate(() => ({ width: document.documentElement.scrollWidth, viewport: innerWidth, overflowing: document.documentElement.scrollWidth > innerWidth + 2, elements: [...document.querySelectorAll('body *')].filter(e => e.getBoundingClientRect().right > innerWidth + 2 && getComputedStyle(e).position !== 'fixed').slice(0, 5).map(e => ({ tag: e.tagName, id: e.id, class: String(e.className).slice(0, 80), right: Math.round(e.getBoundingClientRect().right) })) }));
        if (hubs.has(file)) { await page.bringToFront(); await page.evaluate(()=>scrollTo(0,0)); await page.screenshot({ path: path.join(output, file.replace('.html', '') + '-mobile.png') }); }
        if(visualPages.has(file)){
          result.screenshots=[];
          for(const theme of ['light','dark']){
            const active=await page.evaluate(()=>document.documentElement.dataset.theme||getComputedStyle(document.documentElement).colorScheme);
            if(active!==theme)await page.locator('.theme-toggle').first().click();
            for(const [label,width,height] of [['desktop',1440,900],['mobile',390,844]]){
              await page.setViewportSize({width,height});await page.bringToFront();await page.evaluate(()=>scrollTo(0,0));await page.waitForTimeout(80);
              const name=file.replace(/\//g,'-').replace('.html','')+'-'+theme+'-'+label+'.png';
              await page.screenshot({path:path.join(output,name)});result.screenshots.push(name);
            }
          }
        }
        result.passed = !!dom.title && dom.text_length > 10 && !result.runtime_errors.length && !result.http_errors.length && !result.broken_local_links.length && !result.missing_anchors.length && !result.desktop_overflow && !result.mobile_overflow.overflowing && result.theme.changed && result.theme.persisted && result.theme.returned && !result.theme.contrast.initial.failures.length && !result.theme.contrast.flipped.failures.length;
      } catch (error) { result.passed = false; result.error = error.message; }
      report.pages.push(result); console.log(`${result.passed ? 'PASS' : 'FAIL'} ${file}${result.mobile_overflow?.overflowing ? ' [mobile overflow]' : ''}`);
    }
    await context.close();
  }
  await Promise.all([worker(), worker(), worker()]);
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, acceptDownloads: true }); const page = await context.newPage(); page.on('dialog', d => d.accept()); let interactionErrors = []; page.on('pageerror', error => interactionErrors.push(error.message));
  async function test(name, fn) { try { interactionErrors = []; await fn(); assert.deepEqual(interactionErrors, []); report.interactions.push({ name, passed: true }); console.log('PASS interaction: ' + name); } catch (error) { report.interactions.push({ name, passed: false, error: error.message }); console.log('FAIL interaction: ' + name + ': ' + error.message); } }
  await test('Continuity: scenario/tab keyboard, job edit, search, export and persistence', async () => {
    await page.goto(base + 'sasr_onleave_wiki/Continuity_Toolkit.html'); await page.locator('#tab-jobs').click(); const before = await page.locator('[data-edit]').count(); assert.ok(before > 0);
    await page.locator('[data-edit]').first().click(); await page.locator('#jName').fill('Synthetic QC continuity job'); await page.getByRole('button', { name: 'Save job', exact: true }).click(); await page.locator('#jobFilter').fill('Synthetic QC continuity job'); assert.equal(await page.locator('[data-edit]').count(), 1);
    await page.reload(); await page.locator('#tab-jobs').click(); await page.locator('#jobFilter').fill('Synthetic QC continuity job'); assert.equal(await page.locator('[data-edit]').count(), 1);
    await page.locator('#tab-jobs').focus(); await page.keyboard.press('ArrowRight'); assert.equal(await page.locator('#tab-matrix').getAttribute('aria-selected'), 'true');
    await page.locator('#tab-setup').click(); const radio = page.locator('#scenPick input[type=radio]').last(); await page.locator('label[for="'+await radio.getAttribute('id')+'"]').click(); assert.equal(await radio.isChecked(), true);
    const button = page.locator('[data-act="exportJson"]').first(); const [download] = await Promise.all([page.waitForEvent('download'),button.click()]); const data = JSON.parse(fs.readFileSync(await download.path(), 'utf8')); assert.ok(Array.isArray(data.jobs));
  });
  for (const library of ['sas_tlf_pseudocode', 'r_tlf_pseudocode']) await test(library + ': checklist toggle/reset and source downloads', async () => {
    await page.goto(base + library + '/index.html'); const item = page.locator('#qsc li').first(); await item.click(); assert.match(await item.getAttribute('class') || '', /done/); await page.reload(); assert.match(await page.locator('#qsc li').first().getAttribute('class') || '', /done/); await page.locator('#qscReset').click(); assert.doesNotMatch(await page.locator('#qsc li').first().getAttribute('class') || '', /done/);
    const source = await page.locator(library.startsWith('sas') ? 'a[href$=".sas"]' : 'a[href$=".R"]').first().getAttribute('href'); assert.ok(fs.existsSync(path.resolve(root, library, source)));
  });
  await test('Legacy lifecycle monitor: study selection, heatmap detail, sortable portfolio', async () => {
    await page.goto(base + 'lifecycle_dashboard/Study_Lifecycle_Monitor.html'); await page.locator('#studySel').selectOption('CP-107'); assert.match(await page.locator('#msTitle').textContent(), /CP-107/);
    await page.locator('#heat .cell[data-id="CP-108"]').first().click(); assert.match(await page.locator('#modalBox').textContent(), /CP-108/); await page.locator('.closex').click(); await page.locator('#tbl th').first().click(); assert.equal(await page.locator('#tbl tbody tr').count(), 8);
  });
  await test('TRIALMON static interactive console: roster filters and evidence packet', async () => {
    await page.goto(base + 'sasr_monitoring_wiki/TRIALMON_Dashboard.html'); const roster = page.locator('#subnav button').filter({ hasText: /roster|participants/i }).first(); await roster.click(); await page.locator('#rq').fill('CP101-004'); await page.locator('#rq').dispatchEvent('input'); assert.match(await page.locator('body').textContent(), /CP101-004/); assert.equal(await page.locator('#rosterbody tr').count(),1); const row = page.locator('#rosterbody tr').first(); await row.click(); assert.match(await page.locator('body').textContent(), /CP101-004/);
  });
  await test('UAT and hours guides: real downloadable workbooks are ZIP Office files', async () => {
    for (const [guide, workbook] of [['uat_irt/quarto/uat-guide.html', 'uat_irt/UAT_IRT_RTSM_Workbook.xlsx'], ['budget_reconciliation/quarto/hours-guide.html', 'budget_reconciliation/Hours_Budget_Reconciliation_Workbook.xlsx']]) { await page.goto(base + guide); assert.ok(await page.locator('a[href$=".xlsx"]').count()); const response = await context.request.get(base + workbook); assert.equal(response.status(), 200); assert.equal((await response.body()).subarray(0, 2).toString(), 'PK'); }
  });
  await context.close(); report.passed = report.pages.every(p => p.passed) && report.interactions.every(i => i.passed);
})().catch(error => { report.failures.push(error.stack); report.passed = false; process.exitCode = 1; }).finally(async () => { if (browser) await browser.close(); await new Promise(r => server.close(r)); report.completed_at = new Date().toISOString(); report.pages.sort((a, b) => a.file.localeCompare(b.file)); fs.writeFileSync(path.join(output, 'site-qc-report.json'), JSON.stringify(report, null, 2)); console.log(`Evidence: ${output}; pages ${report.pages.length}, interactions ${report.interactions.length}.`); if (!report.passed) process.exitCode = 1; });
