/* Actual Shinylive/webR method execution, exported artifacts and native parity.
 * NODE_PATH=tools/browser-qc/node_modules CHROME_PATH=/path/to/chrome \
 * QA_OUTPUT_DIR=/path/to/evidence node browser_modules/tests/methods-browser.cjs /path/to/site
 * METHODS_MODULES can select a subset for development; the default tests all four.
 */
'use strict';
const {chromium}=require('playwright');
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),http=require('node:http'),cp=require('node:child_process'),crypto=require('node:crypto');
const repo=path.resolve(__dirname,'../..'),site=path.resolve(process.argv[2]||'_site');
const evidence=path.join(path.resolve(process.env.QA_OUTPUT_DIR||process.argv[3]||'../methods-browser-evidence'),'methods');fs.mkdirSync(evidence,{recursive:true});
const modules=(process.env.METHODS_MODULES||'sandbox,study,carryover,cqtc').split(',');assert(modules.every(x=>['sandbox','study','carryover','cqtc'].includes(x)));
const remote=(process.env.TOOLKIT_PUBLIC_BASE||'').replace(/\/$/,'');if(remote)assert(remote.startsWith('https://'));
const report={passed:false,modules,started_at:new Date().toISOString(),cases:[],errors:[],http_errors:[],requests:[],native_parity:[]};
const mime={'.html':'text/html; charset=utf-8','.js':'text/javascript','.mjs':'text/javascript','.css':'text/css','.json':'application/json','.wasm':'application/wasm','.svg':'image/svg+xml','.png':'image/png','.woff2':'font/woff2','.tgz':'application/gzip','.gz':'application/gzip'};
let server,browser,page,frame,base;
function checkBundle(){
 const bytes=fs.readFileSync(path.join(site,'apps/methods/app.json')),bundle=JSON.parse(bytes);report.bundle_sha256=crypto.createHash('sha256').update(bytes).digest('hex');
 const spec=JSON.parse(fs.readFileSync(path.join(repo,'apps/methods/launch.json')));
 for(const item of [{from:'browser_modules/methods/app.R',to:'app.R'},{from:'browser_modules/methods/methods-ui.js',to:'methods-ui.js'},{from:'browser_modules/methods/methods-ui.css',to:'methods-ui.css'},{from:'apps/_shared/portfolio_app.R',to:'portfolio_app.R'},...spec.extra_files]){
  assert.equal(bundle.find(x=>x.name===item.to)?.content,fs.readFileSync(path.join(repo,item.from),'utf8'),'Export matches reviewed '+item.from);
 }
 return bytes;
}
async function start(){
 const bytes=checkBundle();
 if(remote){assert.deepEqual(Buffer.from(await(await fetch(remote+'/apps/methods/app.json')).arrayBuffer()),bytes,'Published bundle equals reviewed export');base=remote;return;}
 server=http.createServer((req,res)=>{try{
  assert(['GET','HEAD'].includes(req.method));let file=path.resolve(site,'.'+decodeURIComponent(new URL(req.url,'http://localhost').pathname));assert(file.startsWith(site+path.sep)||file===site);
  if(fs.statSync(file).isDirectory())file=path.join(file,'index.html');const stat=fs.statSync(file);assert(stat.isFile());
  res.writeHead(200,{'Content-Type':mime[path.extname(file)]||'application/octet-stream','Content-Length':stat.size,'Cache-Control':'no-cache'});if(req.method==='HEAD')res.end();else fs.createReadStream(file).pipe(res);
 }catch{res.writeHead(404);res.end('Not found');}});
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));base='http://127.0.0.1:'+server.address().port;
}
async function settle(){await page.waitForTimeout(150);await frame.waitForFunction(()=>!document.documentElement.classList.contains('shiny-busy'),null,{timeout:60000});await page.waitForTimeout(200);}
async function configure(kind){await frame.locator('#method').selectOption(kind);await frame.locator('#confirmed').waitFor();await settle();}
async function field(id,value){const control=frame.locator('#'+id);if(await control.getAttribute('type')==='checkbox')await control.setChecked(!!value);else{await control.fill(String(value));await control.dispatchEvent('change');}await settle();}
async function run(kind,label=kind){
 await settle();await frame.locator('#confirmed').check();await settle();assert(await frame.locator('#confirmed').isChecked());assert.equal(await frame.locator('#run').isDisabled(),false);
 const previousRunId=await frame.evaluate(()=>document.querySelector('#method_result')?.dataset.runId||null);
 const start=Date.now();await frame.locator('#run').click();
 // Synchronous R can leave the previous succeeded DOM visible during a repeat.
 // A new run ID, matching module and idle R prove this invocation completed;
 // the short UI settle budget must never become the analysis deadline.
 const afterClick=await frame.evaluate(()=>({state:document.querySelector('#method_state')?.dataset.state,run_id:document.querySelector('#method_result')?.dataset.runId,busy:document.documentElement.classList.contains('shiny-busy'),result_visible:!!document.querySelector('#method_result')?.getClientRects().length,download_disabled:document.querySelector('#download_all')?.disabled,progress:[...document.querySelectorAll('.shiny-progress-notification')].map(x=>x.innerText)}));
 report.current_run={kind,case:label,previous_run_id:previousRunId,after_click:afterClick};
 await frame.waitForFunction(({kind,previousRunId})=>{
  const state=document.querySelector('#method_state')?.dataset.state,result=document.querySelector('#method_result');
  if(document.documentElement.classList.contains('shiny-busy'))return false;
  return state==='error'||(state==='succeeded'&&result?.dataset.module===kind&&!!result.dataset.runId&&result.dataset.runId!==previousRunId);
 },{kind,previousRunId},{timeout:900000});
 assert.equal(await frame.locator('#method_state').getAttribute('data-state'),'succeeded',await frame.locator('#method_state').innerText());
 const runId=await frame.locator('#method_result[data-module="'+kind+'"]').getAttribute('data-run-id');assert(runId&&runId!==previousRunId,'A distinct completed run must replace the previous result');await settle();
 const pending=page.waitForEvent('download',{timeout:60000});await frame.locator('#download_all').click();const item=await pending,file=path.join(evidence,label+'.zip');await item.saveAs(file);assert.equal(await item.failure(),null);const browserElapsed=Date.now()-start;
 const directory=path.join(evidence,'extracted',label);
 cp.execFileSync(process.env.TOOLKIT_PYTHON||'python3',['-c',`import sys,zipfile,pathlib,csv,hashlib,re
from html.parser import HTMLParser
archive,directory=sys.argv[1:];root=pathlib.Path(directory)
with zipfile.ZipFile(archive) as z:
 assert z.testzip() is None
 names=z.namelist();assert len(names)==len(set(names))
 for n in names:
  p=pathlib.PurePosixPath(n);assert not p.is_absolute() and '..' not in p.parts and '\\\\' not in n
 z.extractall(root)
for row in csv.DictReader((root/'file_inventory.csv').open()):assert hashlib.md5((root/row['file']).read_bytes()).hexdigest()==row['md5']
for p in root.rglob('*'):
 if p.suffix not in ['.html','.csv','.json','.log','.txt']:continue
 text=p.read_text();assert '/Users/' not in text and '/var/folders/' not in text
 if p.suffix!='.html' or '_partials' in p.parts:continue
 assert 'theme-toggle' in text and 'assets/ui.js' in text, str(p)
 for target in re.findall(r'(?:src|href)="([^"#]+)"',text):
  if re.match(r'^[a-zA-Z]+:|^/',target):continue
  target=target.split('#')[0].split('?')[0]
  assert (p.parent/target).exists(),(p,target)
` ,file,directory],{encoding:'utf8'});
 const native=path.join(evidence,'native',label);fs.mkdirSync(path.dirname(native),{recursive:true});assert(!fs.existsSync(native),'Use a fresh evidence directory');
 const output=cp.execFileSync(process.env.RSCRIPT||'Rscript',[path.join(repo,'browser_modules/tests/methods-browser-parity.R'),repo,directory,native],{cwd:repo,encoding:'utf8',timeout:300000,maxBuffer:16*1024*1024});
 fs.writeFileSync(path.join(evidence,label+'-native.log'),output);const parity=JSON.parse(output.trim().split('\n').at(-1));report.native_parity.push({...parity,case:label});
 report.cases.push({kind,case:label,passed:true,run_id:runId,previous_run_id:previousRunId,after_click:afterClick,browser_compute_download_ms:browserElapsed,zip_bytes:fs.statSync(file).size});delete report.current_run;console.log('PASS '+label+' actual browser execution, ZIP integrity and native parity');
}
async function themesAndPhone(kind){
 for(const theme of ['light','dark']){
  if(await page.evaluate(()=>document.documentElement.getAttribute('data-theme')||(matchMedia('(prefers-color-scheme: light)').matches?'light':'dark'))!==theme)await page.locator('header.top .theme-toggle').click();
  await frame.waitForFunction(want=>document.documentElement.getAttribute('data-bs-theme')===want&&window.Shiny?.shinyapp?.$inputValues.bp_theme===want,theme);await settle();
  await page.screenshot({path:path.join(evidence,kind+'-results-'+theme+'.png'),fullPage:false});
 }
 await page.setViewportSize({width:390,height:844});await settle();
 const dimensions=await frame.evaluate(()=>({page:document.documentElement.scrollWidth,body:document.body.scrollWidth,viewport:innerWidth}));
 assert(dimensions.page<=dimensions.viewport+1&&dimensions.body<=dimensions.viewport+1,JSON.stringify(dimensions));
 await frame.locator('#method').scrollIntoViewIfNeeded();await page.screenshot({path:path.join(evidence,kind+'-phone.png'),fullPage:false});
 await page.setViewportSize({width:1440,height:1000});await settle();report.cases.push({case:'both-themes-and-phone',passed:true,dimensions});
}
(async()=>{
 await start();browser=await chromium.launch({headless:true,executablePath:process.env.CHROME_PATH||undefined});page=await browser.newPage({acceptDownloads:true,viewport:{width:1440,height:1000}});
 page.on('pageerror',e=>report.errors.push(e.message));page.on('response',r=>{if(r.status()>=400)report.http_errors.push({status:r.status(),url:r.url()});});page.on('request',r=>report.requests.push({url:r.url(),method:r.method()}));
 await page.goto(base+'/apps/methods/?module=study');await page.waitForFunction(()=>window.launchStatus?.ready,null,{timeout:300000});
 frame=page.frames().find(f=>/\/app_[^/]+\//.test(f.url()));assert(frame);await settle();assert.equal(await frame.locator('#method').inputValue(),'study','Query selects form without execution');assert.equal(await frame.locator('#method_result').count(),0);
 await frame.locator('#reset').click();await settle();assert.equal(await frame.locator('#method').inputValue(),'');assert(await frame.locator('#run').isDisabled());
 for(const kind of modules){
  await configure(kind);
  if(kind==='carryover'){
   await field('replicates',20);await field('theta','1');await field('washouts','2, 10');
   await frame.locator('input[name="disposition"][value="biexp"]').check();await settle();
   for(const value of ['assay','extended']){await frame.locator('input[name="configurations"][value="'+value+'"]').check();await settle();}
  }
  if(kind==='cqtc'){
   const choices=await frame.locator('#scenarios option').evaluateAll(nodes=>nodes.map(n=>n.value));assert.equal(choices.length,32);await frame.locator('#scenarios').selectOption(choices);await settle();
   await field('replicates',20);await field('sign_vectors',99);await field('bootstrap',99);await field('controls',true);
  }
  await run(kind);if(kind==='study')await run(kind,'study-repeat');await themesAndPhone(kind);
  if(kind==='carryover'){
   await field('n',13);assert.equal(await frame.locator('#method_result').count(),0);assert.equal(await frame.locator('#confirmed').isChecked(),false);assert(await frame.locator('#run').isDisabled());
   await frame.locator('#confirmed').check();await settle();await frame.locator('#run').click();await frame.locator('#method_state[data-state="error"]').waitFor();assert.match(await frame.locator('#method_state').innerText(),/even participant/);
   report.cases.push({case:'invalid-input-and-stale-results',passed:true});
  }
 }
 await frame.locator('#reset').click();await settle();assert.equal(await frame.locator('#method_result').count(),0);assert.equal(await frame.locator('#method').inputValue(),'');
 const external=report.requests.filter(r=>/^https?:/.test(r.url)&&!r.url.startsWith(base+'/'));assert.deepEqual(external,[]);assert(report.requests.every(r=>['GET','HEAD'].includes(r.method)));assert.deepEqual(report.errors,[]);assert.deepEqual(report.http_errors,[]);report.passed=true;
})().catch(async error=>{report.failure=String(error.stack||error);if(frame)report.failure_body=await frame.locator('body').innerText().catch(()=>'');console.error(report.failure);process.exitCode=1;}).finally(async()=>{fs.writeFileSync(path.join(evidence,'report.json'),JSON.stringify(report,null,2));await browser?.close();await new Promise(resolve=>server?server.close(resolve):resolve());});
