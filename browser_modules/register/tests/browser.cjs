// Actual browser interactions; run against the repository or a published build.
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const assert=require('node:assert/strict'),fs=require('node:fs/promises'),path=require('node:path');
const base=process.argv[2]||'http://127.0.0.1:8000',output=process.argv[3]||'/tmp/toolkit-register-browser-qc';
// the starter's size comes from the data, so the check follows the register when deliverables are added
const N=JSON.parse(require('node:fs').readFileSync(path.join(__dirname,'../../../biostat_pipeline/_register.json'),'utf8')).length;
(async()=>{
 await fs.mkdir(output,{recursive:true});
 const browser=await chromium.launch({headless:true,...(process.env.CHROME_PATH?{executablePath:process.env.CHROME_PATH}:{channel:'chrome'})});
 const context=await browser.newContext({acceptDownloads:true,viewport:{width:1440,height:1000}}),page=await context.newPage();
 const errors=[],requests=[];page.on('pageerror',e=>errors.push(e.message));page.on('request',r=>requests.push({url:r.url(),method:r.method()}));page.on('dialog',d=>d.accept());
 const report={passed:false,checks:[]};
 const check=x=>{report.checks.push(x);console.log('PASS',x);};
 const count=async n=>assert.match(await page.locator('#count').innerText(),new RegExp('of '+n+' rows$'));
 const exportFile=async(button,file)=>{const event=page.waitForEvent('download');await page.locator(button).click();const downloaded=await event;const target=path.join(output,file);await downloaded.saveAs(target);return fs.readFile(target,'utf8');};
 try{
  await page.goto(base+'/browser_modules/register/',{waitUntil:'networkidle'});await count(0);
  assert.equal(await page.locator('#study').inputValue(),'');assert.ok(!requests.some(r=>r.url.endsWith('/_register.json')));check('Blank, client-neutral initial state; starter data fetch requires explicit click');
  await page.locator('#starter').click();await page.waitForFunction(n=>document.querySelector('#count').textContent===`${n} of ${n} rows`,N);check(`All ${N} canonical starter rows load`);
  await page.locator('#study').fill('QC-STUDY-NO-CLIENT');await page.locator('[data-id="S1-01"]').click();
  await page.locator('#row-owner').fill('Independent review role');await page.locator('#row-status').selectOption('In progress');await page.locator('#row-due_date').fill('2027-01-15');
  await page.locator('#reset').click();assert.match(await page.locator('#error').innerText(),/Save or discard/);await count(N);
  await page.getByRole('button',{name:'Save deliverable',exact:true}).click();await count(N);check('Guided editing, saved status/date and protection against losing unsaved edits');
  await page.locator('#new').click();await page.locator('#row-deliverable').fill('<img src="https://invalid.example/collect" onerror="window.BAD=1">');await page.locator('#row-owner').fill('=1+1');await page.locator('#row-notes').fill('Long note, "quoted"\nsecond line Δ');
  await page.getByRole('button',{name:'Save deliverable',exact:true}).click();await count(N+1);assert.equal(await page.locator('.records img').count(),0);assert.equal(await page.evaluate(()=>window.BAD),undefined);check('New records accept Unicode/multiline text and render imported markup literally');
  await page.locator('#search').fill('Long note');assert.equal(await page.locator('#count').innerText(),`1 of ${N+1} rows`);
  const json=JSON.parse(await exportFile('#json','full-register.json'));assert.equal(json.rows.length,N+1);assert.equal(json.study,'QC-STUDY-NO-CLIENT');assert.equal(json.rows[0].owner,'Independent review role');assert.equal(json.rows[0].due_date,'2027-01-15');assert.equal(json.rows.at(-1).owner,'=1+1');assert.equal(Object.keys(json.rows[0]).length,15);assert.ok(!('approved'in json));
  const csv=await exportFile('#csv','full-register.csv');assert.ok(csv.includes('"\'=1+1"'));check('Complete lossless JSON and formula-safe CSV export every row regardless of filters');
  await page.locator('#import').setInputFiles({name:'bad.csv',mimeType:'text/csv',buffer:Buffer.from('id,deliverable\nDUP,a\nDUP,b')});await page.waitForFunction(()=>!document.querySelector('#error').hidden&&document.querySelector('#error').textContent.includes('Duplicate'));await count(N+1);check('Invalid import fails atomically and preserves the current register');
  await page.locator('#import').setInputFiles(path.join(output,'full-register.json'));await page.waitForFunction(n=>document.querySelector('#count').textContent===`${n} of ${n} rows`,N+1);assert.equal(await page.locator('#study').inputValue(),'QC-STUDY-NO-CLIENT');check('Complete JSON round-trip restores study label and all rows');
  await page.locator('#search').fill('Long note');await page.locator('[data-id="ROW-001"]').click();await page.locator('#delete').click();await count(N);await page.locator('#undo').click();await count(N+1);await page.locator('#reset').click();await count(0);await page.locator('#undo').click();await count(N+1);check('Remove, reset and undo preserve recoverable complete state');
  await page.locator('#stage').selectOption({label:'Stage 1: Study design & protocol'});assert.ok((await page.locator('.record').count())>1);await page.locator('#status-filter').selectOption('In progress');assert.equal(await page.locator('.record').count(),1);check('Stage, planning-status and all-field search filters work independently');
  await page.evaluate(()=>{window.print=()=>{window.PRINT_CALLED=true;};});await page.locator('#print').click();assert.equal(await page.locator('#printout article').count(),N+1);assert.equal(await page.evaluate(()=>window.PRINT_CALLED),true);check('Print retains all rows and all fields, with no implied approval');
  const initial=await page.locator('.theme-toggle').getAttribute('aria-pressed');await page.locator('.theme-toggle').click();assert.notEqual(await page.locator('.theme-toggle').getAttribute('aria-pressed'),initial);await page.screenshot({path:path.join(output,'desktop-theme.png'),fullPage:false});
  await page.locator('.theme-toggle').click();await page.setViewportSize({width:390,height:844});assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await page.screenshot({path:path.join(output,'phone.png'),fullPage:false});check('Shared light/dark option and 390px phone layout work without page overflow');
  assert.deepEqual(await page.evaluate(()=>Object.keys(localStorage).filter(k=>k!=='bp-theme')),[]);assert.equal(await page.evaluate(()=>sessionStorage.length),0);
  await page.reload({waitUntil:'networkidle'});await count(0);assert.equal(await page.locator('#study').inputValue(),'');check('Study records remain only in tab memory and are cleared on reload');
  assert.ok(requests.every(r=>r.method==='GET'&&new URL(r.url).origin===new URL(base).origin));assert.ok(!requests.some(r=>r.url.includes('QC-STUDY-NO-CLIENT')));assert.deepEqual(errors,[]);check('No external requests, data POSTs, study content in URLs or browser errors');
  report.passed=true;
 }catch(error){report.error=String(error.stack||error);throw error;}
 finally{report.requests=requests;report.errors=errors;await fs.writeFile(path.join(output,'report.json'),JSON.stringify(report,null,2));await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
