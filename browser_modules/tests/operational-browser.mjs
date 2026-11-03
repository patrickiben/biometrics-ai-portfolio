// Real webR/Shiny browser QC: no native R server, real file picker, client-side ZIP and complete restoration.
// node browser_modules/tests/operational-browser.mjs SITE EVIDENCE [risk,hours,...]
import fs from 'node:fs';import path from 'node:path';import http from 'node:http';import assert from 'node:assert/strict';import {createRequire} from 'node:module';
const require=createRequire(path.resolve('.github/pages/smoke/package.json')),puppeteer=require('puppeteer-core');
const [siteArg,evidenceArg,selection='risk,hours,uat_irt,lifecycle_dashboard,trialmon']=process.argv.slice(2),site=path.resolve(siteArg),evidence=path.resolve(evidenceArg);
fs.mkdirSync(evidence,{recursive:true});const prefix='/biometrics-ai-portfolio',mime={'.html':'text/html','.js':'text/javascript','.mjs':'text/javascript','.css':'text/css','.wasm':'application/wasm','.json':'application/json','.svg':'image/svg+xml','.png':'image/png','.webp':'image/webp','.woff2':'font/woff2','.tgz':'application/gzip'};
const server=http.createServer((req,res)=>{let url=new URL(req.url,'http://x'),file=path.resolve(site,'.'+decodeURIComponent(url.pathname).slice(prefix.length));if(!url.pathname.startsWith(prefix+'/')||!file.startsWith(site+'/')){res.writeHead(404).end();return;}try{if(fs.statSync(file).isDirectory())file=path.join(file,'index.html');let stat=fs.statSync(file);res.writeHead(200,{'Content-Type':mime[path.extname(file)]||'application/octet-stream','Content-Length':stat.size});fs.createReadStream(file).pipe(res);}catch{res.writeHead(404).end();}});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const base=`http://127.0.0.1:${server.address().port}${prefix}`;
const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));
function unpack(buffer){const entries={};let p=0;while(buffer.readUInt32LE(p)===0x04034b50){assert.equal(buffer.readUInt16LE(p+8),0);const size=buffer.readUInt32LE(p+18),names=buffer.readUInt16LE(p+26),extra=buffer.readUInt16LE(p+28),start=p+30+names+extra;entries[buffer.subarray(p+30,p+30+names).toString()]=buffer.subarray(start,start+size).toString();p=start+size;}assert.equal(buffer.readUInt32LE(p),0x02014b50);return entries;}
const report=[];
try{
for(const app of selection.split(',')){
 const folder=path.join(evidence,app);fs.mkdirSync(folder,{recursive:true});const browser=await puppeteer.launch({executablePath:process.env.CHROME_PATH||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
 try{
  const page=await browser.newPage();await page.setViewport({width:1360,height:1000});const errors=[];page.on('pageerror',e=>errors.push(String(e)));
  const cdp=await page.createCDPSession();await cdp.send('Page.setDownloadBehavior',{behavior:'allow',downloadPath:folder});
  await page.goto(`${base}/apps/${app}/`);await page.waitForFunction(()=>window.launchStatus?.ready||window.launchStatus?.problem,{timeout:150000});const launch=await page.evaluate(()=>window.launchStatus);assert.equal(launch.problem,null,JSON.stringify(launch.events));
  const frame=page.frames().find(f=>/app_/.test(f.url()));assert(frame);await frame.waitForSelector('#bw_status .bw-status[data-active="false"]');assert(await frame.$eval('#bw_export',e=>e.disabled));
  assert(await frame.evaluate(()=>[...document.body.children].filter(e=>e.id!=='bw_workspace'&&!['SCRIPT','STYLE','LINK'].includes(e.tagName)).every(e=>getComputedStyle(e).display==='none')));
  const top=await page.$eval('.top',e=>e.textContent);assert(!/Status pending.*GREEN/.test(top));await page.screenshot({path:path.join(folder,'blank.png'),fullPage:true});
  async function ready(){await frame.waitForFunction(()=>document.querySelector('#bw_status .bw-status')?.dataset.active==='true'&&document.body.dataset.bwState==='ready'&&!document.documentElement.classList.contains('shiny-busy'),{timeout:45000});await wait(400);}
  let downloads=0;
  async function download(){const before=new Set(fs.readdirSync(folder));await frame.click('#bw_export');let candidate;for(let i=0;i<200;i++){candidate=fs.readdirSync(folder).find(n=>!before.has(n)&&n.endsWith('.zip'));if(candidate){try{const data=fs.readFileSync(path.join(folder,candidate));if(data.length>=22&&data.readUInt32LE(data.length-22)===0x06054b50)break;}catch{}candidate=undefined;}await wait(100);}assert(candidate,'complete workspace download');const content=fs.readFileSync(path.join(folder,candidate));fs.renameSync(path.join(folder,candidate),path.join(folder,`download-${++downloads}.zip`));return unpack(content);}
  async function upload(files){await frame.click('#bw_change');const input=await frame.$('#bw_files');await input.uploadFile(...files);await frame.waitForSelector('#bw_apply',{visible:true,timeout:20000});await wait(600);}
  async function apply(){const confirm=await frame.$('input[id^="bw_confirm_"]');await confirm.click();await frame.click('#bw_apply');try{await ready();}catch(error){throw Error(`${app}: ${await frame.$eval('#bw_message',e=>e.textContent)} (${error.message})`);}}
  await frame.click('#bw_example');await ready();const initial=await download(),jsonName=Object.keys(initial).find(n=>n.endsWith('-workspace.json')),saved=JSON.parse(initial[jsonName]);
  assert(Object.keys(initial).some(n=>n.startsWith('outputs/')));assert(Object.keys(initial).some(n=>n.startsWith('source/')));
  // Use different identifiers from every bundled CP/RAND scenario; preserve cross-table references.
  const custom={...saved,inputs:Object.fromEntries(Object.entries(saved.inputs).map(([name,csv])=>[name,(app==='hours'?csv.replaceAll('SAP','QC SAP'):csv).replaceAll('CP','STUDY').replaceAll('RAND-04','CHECK-04').replaceAll('S-1042','CASE-0042')]))};
  const files=Object.entries(custom.inputs).map(([name,csv])=>{const file=path.join(folder,name);fs.writeFileSync(file,csv);return file;});
  // Supply CSVs through the actual browser file picker. Also exercise noncanonical column names on the first feed.
  let first=fs.readFileSync(files[0],'utf8'),header=first.slice(0,first.indexOf('\n'));const firstName=/^"([^"]+)"/.exec(header)?.[1]||header.split(',')[0];first=first.replace(/^"?[A-Za-z_][A-Za-z0-9_]*"?/, 'source_field');fs.writeFileSync(files[0],first);
  await upload(files);assert(await frame.$eval('#bw_export',e=>e.disabled));const missing=await frame.$('#bw_map_2_1_1');assert(missing);await frame.select('#bw_map_2_1_1','source_field');
  if(app==='trialmon'){
    await frame.evaluate(cfg=>{
      const values={bw_schedule:Object.entries(cfg.schedule).map(([visit,day])=>`${visit} = ${day}`).join('\n'),bw_sae_amber:cfg.sae_limits[0],bw_sae_red:cfg.sae_limits[1],bw_missing_amber:cfg.missing_limits[0],bw_missing_red:cfg.missing_limits[1],bw_lab_ctcae:cfg.ctcae,bw_ae_ctcae:cfg.ae_ctcae,bw_window:cfg.hys_window,bw_meddra:cfg.meddra};
      for(const [id,value] of Object.entries(values)){const e=document.getElementById(id);e.value=value;e.dispatchEvent(new Event('change',{bubbles:true}));}
    },saved.settings);
  }
  await apply();
  const customExport=await download(),back=JSON.parse(customExport[jsonName]);for(const name of Object.keys(custom.inputs))assert.equal(back.inputs[name],custom.inputs[name],`${app}: mapped input ${name}`);
  // Real edit controls, then all editable state is preserved on JSON restore.
  if(app==='hours'){await frame.click('#need',{clickCount:3});await page.keyboard.press('Backspace');await page.keyboard.type('59.5');await page.keyboard.press('Tab');await wait(900);}
  if(app==='lifecycle_dashboard'){await frame.select('#study','STUDY-103');await wait(800);}
  if(app==='uat_irt'){await frame.click('[data-uat-status="Fail"]');await wait(700);}
  const edited=await download(),editedSaved=JSON.parse(edited[jsonName]);if(app==='hours')assert.equal(editedSaved.settings.need,59.5);if(app==='uat_irt')assert.notEqual(editedSaved.inputs['test_scripts.csv'],back.inputs['test_scripts.csv']);
  const restored=path.join(folder,'restore.json');fs.writeFileSync(restored,edited[jsonName]);await upload([restored]);await apply();const roundtrip=await download(),roundSaved=JSON.parse(roundtrip[jsonName]);assert.deepEqual(roundSaved.inputs,editedSaved.inputs);assert.deepEqual(roundSaved.settings,editedSaved.settings);
  // Replace the valid workspace with malformed input: old tables and exports must disappear immediately.
  const bad=path.join(folder,'malformed.csv');fs.writeFileSync(bad,'same,same\n1,2');await frame.click('#bw_change');await (await frame.$('#bw_files')).uploadFile(bad);await frame.waitForSelector('.bw-error',{timeout:15000});assert(await frame.$eval('#bw_export',e=>e.disabled));assert(await frame.evaluate(()=>[...document.body.children].filter(e=>e.id!=='bw_workspace'&&!['SCRIPT','STYLE','LINK'].includes(e.tagName)).every(e=>getComputedStyle(e).display==='none')));
  if(['trialmon','lifecycle_dashboard','uat_irt'].includes(app)){await wait(700);assert.equal(await page.$eval('.top .mc-status',e=>e.classList.contains('pending')),true);}
  await frame.click('#bw_example');await ready();await frame.click('#bw_reset');await frame.waitForSelector('#bw_status .bw-status[data-active="false"]');assert(await frame.$eval('#bw_export',e=>e.disabled));
  // Blank setup remains operable at phone width and follows both themes.
  await page.setViewport({width:390,height:844});await wait(300);assert(await frame.$eval('#bw_workspace',e=>e.getBoundingClientRect().right<=innerWidth+1));await page.screenshot({path:path.join(folder,'phone-blank.png'),fullPage:true});assert.deepEqual(errors,[]);
  report.push({app,passed:true,inputs:Object.keys(saved.inputs).length,outputs:Object.keys(initial).filter(n=>n.startsWith('outputs/')).length,checks:['blank','CSV mapping','custom identifiers','ZIP inputs/results/source','editable settings','JSON restore','malformed replacement','export disabled','status cleared','reset','phone setup']});console.log(app,'PASS',report.at(-1));
 }catch(error){report.push({app,passed:false,error:String(error.stack||error)});console.error(app,error);}
 finally{await browser.close();fs.writeFileSync(path.join(evidence,'report.json'),JSON.stringify(report,null,2));}
}
}finally{server.close();}
if(report.some(r=>!r.passed))process.exitCode=1;
