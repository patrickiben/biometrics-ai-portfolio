/* Actual stlite/Pyodide integration QC. No mocked analysis or synthetic UI events.
 * node tests/browser_qc.cjs SITE_ROOT; CHROME_PATH and QA_OUTPUT_DIR are optional.
 * TOOLKIT_PUBLIC_BASE can select the deployed site while SITE_ROOT remains the
 * source/bundle oracle. Every uploaded fixture is fictional.
 */
const {chromium}=require('playwright');
const fs=require('node:fs'),path=require('node:path'),http=require('node:http');
const assert=require('node:assert/strict'),crypto=require('node:crypto');
const {execFileSync}=require('node:child_process');
const site=path.resolve(process.argv[2]||path.join(__dirname,'../..'));
const out=path.resolve(process.env.QA_OUTPUT_DIR||path.join(site,'ecrf-browser-qc'));
fs.mkdirSync(out,{recursive:true});
const report={started:new Date().toISOString(),runtime:'actual stlite/Pyodide',apps:[],errors:[]};
if(process.env.ECRF_QC_APP&&!['meddra','phi','risk','anomaly'].includes(process.env.ECRF_QC_APP))throw Error('Unknown ECRF_QC_APP');
report.scope=process.env.ECRF_QC_APP||'all four apps';
const digest=b=>crypto.createHash('sha256').update(b).digest('hex');
const csv=rows=>rows.map(r=>r.map(v=>'"'+String(v).replaceAll('"','""')+'"').join(',')).join('\n')+'\n';
const upload=(name,text)=>({name,mimeType:'text/csv',buffer:Buffer.from(text)});
const hostile='<img src=x onerror="globalThis.ecrfXSS=1">';
const privacyMarker='ECRF_PRIVATE_QC_624089';
const fixture={
  study:upload('study.custom.csv',csv([['protocol','person','event','description','unselected'],[privacyMarker,'001','1','head pain','PRIVATE_UNUSED_COLUMN'],[privacyMarker,'002','2','=1+1','PRIVATE_UNUSED_COLUMN'],[privacyMarker,'003','3',hostile,'PRIVATE_UNUSED_COLUMN']])),
  dictionary:upload('dictionary.custom.csv',csv([['word','preferred','identifier','status'],['head pain','Headache','QC001','Y'],['=1+1','=1+1','QC002','Y'],[hostile,hostile,'QC003','Y'],['head pain','INACTIVE_TERM','QC999','N']])),
  phi:upload('notes.custom.csv',csv([['record','notes','=1+1'],['001','Contact Alice Example at alice@example.invalid; phone 202-555-0189. '+privacyMarker+' Orion at 212-555-1234','=SUM(1,2)'],['002','No identifying contact recorded.','ordinary']])),
  risk:upload('cardiac.custom.csv',csv([['protocol','person','interval','units'],[privacyMarker,'001','490','ms'],[privacyMarker,'001','500','ms'],[privacyMarker,'002','501','ms']])),
  anomaly:upload('measurements.custom.csv',csv([['protocol','person','visit','site','measurement','units'],...['A','B'].flatMap(lab=>[1,2,3].flatMap(i=>[0,1].map(t=>[privacyMarker,lab+i,t,lab,10*i+(lab==='B'&&t===1?20:0),'U/L'])))])),
  bad:upload('malformed.csv','id,value\n1,2,3\n')
};
async function settled(page){
  // Observe the actual React output, including worker-driven rerenders. A stale
  // notRunning attribute alone can precede delivery of the next script request.
  await page.evaluate(()=>{
    globalThis.ecrfQcObserver?.disconnect();globalThis.ecrfQcChanged=performance.now();
    globalThis.ecrfQcObserver=new MutationObserver(()=>{globalThis.ecrfQcChanged=performance.now();});
    globalThis.ecrfQcObserver.observe(document.querySelector('#root'),{childList:true,subtree:true,attributes:true,characterData:true});
  });
  await page.waitForFunction(()=>document.querySelector('[data-testid="stApp"]')?.dataset.testScriptState==='notRunning'&&performance.now()-globalThis.ecrfQcChanged>700,{},{timeout:60000});
  assert.equal(await page.locator('[data-testid="stException"]').count(),0,'No Streamlit exception');
}
async function click(page,name){await page.getByRole('button',{name,exact:true}).click();await settled(page);}
async function select(page,label,value){
  const control=page.locator('[data-testid="stSelectbox"]').filter({has:page.getByText(label,{exact:true})});
  if(await control.getByRole('combobox').inputValue()===value)return;
  // Keep the opening popover away from the viewport edge. React Aria replaces
  // the options while flipping a bottom-edge popover, which invalidates a click.
  await control.evaluate(e=>e.scrollIntoView({block:'center',behavior:'instant'}));await page.waitForTimeout(180);
  // Real keyboard input avoids trying to click a virtualized option while its
  // popover is repositioning. The selected value is still checked afterward.
  await control.getByRole('combobox').fill(value);
  await page.getByRole('option',{name:value,exact:true}).waitFor({state:'visible'});
  await control.getByRole('combobox').press('ArrowDown');await control.getByRole('combobox').press('Enter');await settled(page);
  assert.equal(await control.getByRole('combobox').inputValue(),value,'Mapped '+label);
}
async function fill(page,label,value){await page.getByLabel(label,{exact:true}).fill(value);await page.getByLabel(label,{exact:true}).press('Tab');await settled(page);}
async function files(page,index,items){await page.locator('input[type=file]').nth(index).setInputFiles(items);await settled(page);}
async function check(page,pattern){
  const box=page.getByRole('checkbox',{name:pattern});
  if(!await box.isChecked())await page.getByText(pattern).click();
  await settled(page);assert.ok(await box.isChecked(),'Review confirmation selected');
}
async function absent(page,label){assert.equal(await page.getByRole('button',{name:label,exact:true}).count(),0,'Old download unavailable after input change');}
async function download(page,label,dest){
  const promise=page.waitForEvent('download',{timeout:30000});await page.getByRole('button',{name:label,exact:true}).click();
  const dl=await promise;await dl.saveAs(dest);assert.equal(await dl.failure(),null);assert.ok(fs.statSync(dest).size>0);return dest;
}
function zip(file){
  return JSON.parse(execFileSync(process.env.PYTHON||'python3',['-c',
    'import csv,io,json,sys,zipfile,hashlib\nz=zipfile.ZipFile(sys.argv[1]);assert z.testzip() is None\nf={n:z.read(n).decode("utf-8") for n in z.namelist()}\nprint(json.dumps({"files":f,"csv":{n:list(csv.DictReader(io.StringIO(s))) for n,s in f.items() if n.endswith(".csv")},"sha256":{n:hashlib.sha256(z.read(n)).hexdigest() for n in z.namelist()}}))',file],{maxBuffer:20*1024*1024}).toString());
}
async function themesAndPhone(page,dir,downloadLabel){
  const before=await download(page,downloadLabel,path.join(dir,'before-theme.zip'));
  const colors=[];
  for(const theme of ['dark','light']){
    if(await page.locator('html').getAttribute('data-theme')!==theme)await page.locator('.theme-toggle').click();
    await page.waitForFunction(t=>document.documentElement.dataset.theme===t,theme);await page.waitForTimeout(200);
    colors.push(await page.locator('[data-testid="stApp"]').evaluate(e=>getComputedStyle(e).backgroundColor));
    assert.ok(await page.locator('[data-testid="stDataFrame"]').count()>0,'Results table remains rendered');
    assert.equal(await page.evaluate(()=>globalThis.ecrfXSS||0),0,'Uploaded markup inert');
    await page.screenshot({path:path.join(dir,theme+'.png'),fullPage:true});
  }
  assert.notEqual(colors[0],colors[1],'Actual Streamlit theme changes');
  const after=await download(page,downloadLabel,path.join(dir,'after-theme.zip'));
  assert.equal(digest(fs.readFileSync(before)),digest(fs.readFileSync(after)),'Theme switches preserve exact results');
  await page.setViewportSize({width:390,height:844});
  await page.getByRole('button',{name:downloadLabel,exact:true}).scrollIntoViewIfNeeded();await page.waitForTimeout(250);
  const bounds=await page.getByRole('button',{name:downloadLabel,exact:true}).boundingBox();
  assert.ok(bounds&&bounds.width>100&&bounds.x>=-1&&bounds.x+bounds.width<=391,'Phone result download is usable');
  const overflow=await page.evaluate(()=>document.documentElement.scrollWidth-window.innerWidth);assert.ok(overflow<=1,'No document horizontal overflow');
  await page.screenshot({path:path.join(dir,'phone-results.png'),fullPage:true});
  return {colors,result_sha256:digest(fs.readFileSync(after)),phone_width:390};
}
async function runCoding(page,dir,r){
  await files(page,0,fixture.study);await absent(page,'Download complete coding package');
  assert.ok((await page.locator('body').innerText()).includes('No example dictionary is used'));
  await files(page,1,fixture.dictionary);
  for(const [label,value] of [['Verbatim column','description'],['Study identifier (optional)','protocol'],['Participant identifier (optional)','person'],['Event key (optional)','event'],['Dictionary term','word'],['Preferred-term name','preferred'],['Term code (optional)','identifier'],['Active/currency column (optional)','status']])await select(page,label,value);
  await fill(page,'Dictionary name/version (optional)','Fictional QC dictionary');await click(page,'Run coding suggestions');
  const z=zip(await download(page,'Download complete coding package',path.join(dir,'coding.zip')));
  const rows=z.csv['coding_candidates.csv'];assert.ok(rows.length>=3);assert.ok(rows.every(x=>x.REVIEW_STATUS==='UNREVIEWED_CANDIDATE'));
  assert.equal(rows.filter(x=>x.TERM_CODE==='QC999').length,0);assert.equal(new Set(rows.map(x=>x.SOURCE_ROW)).size,3);
  assert.ok(rows.some(x=>x.PARTICIPANT_ID==='001'));assert.ok(rows.some(x=>x.VERBATIM==="'=1+1"));
  assert.ok(!JSON.stringify(z.files).includes('PRIVATE_UNUSED_COLUMN'));assert.ok(!JSON.parse(z.files['study_setup.json']).example);
  assert.ok(JSON.parse(z.files['coding_candidates.json']).some(x=>x.VERBATIM==='=1+1'));
  r.theme=await themesAndPhone(page,dir,'Download complete coding package');
  await page.setViewportSize({width:1440,height:1000});await fill(page,'Dictionary name/version (optional)','Changed dictionary provenance');await absent(page,'Download complete coding package');
  await click(page,'Run coding suggestions');await files(page,1,fixture.bad);await absent(page,'Download complete coding package');
  assert.ok(await page.locator('[data-testid="stAlertContainer"]').count()>0);r.assertions='custom study/dictionary mappings, active filter, unreviewed rows, formula-safe/lossless exports, unselected fields excluded, stale settings and malformed dictionary';
}
async function runPhi(page,dir,r){
  await files(page,0,fixture.phi);await fill(page,'Additional literal terms to redact (one per line)','Alice Example\n'+privacyMarker+'\nOrion at 212-555-1234');await click(page,'Run de-identification review');
  const clean=zip(await download(page,'Download redacted package',path.join(dir,'redacted.zip')));
  for(const text of Object.values(clean.files))for(const secret of ['Alice Example','alice@example.invalid','202-555-0189',privacyMarker,'Orion','212-555-1234'])assert.ok(!text.includes(secret),'Clean package excludes '+secret);
  assert.deepEqual(Object.keys(clean.csv['redacted/input_01.csv'][0]),['record','notes',"'=1+1"]);
  assert.equal(clean.csv['redacted/input_01.csv'][0]["'=1+1"],"'=SUM(1,2)");
  await page.getByText('Sensitive review details',{exact:true}).click();
  const sensitive=zip(await download(page,'Download sensitive review package',path.join(dir,'sensitive.zip')));
  assert.ok(sensitive.files['selected_original_fields.json'].includes('Alice Example'));assert.ok(sensitive.files['review_setup.json'].includes(privacyMarker));
  r.theme=await themesAndPhone(page,dir,'Download redacted package');
  await page.setViewportSize({width:1440,height:1000});await fill(page,'Additional literal terms to redact (one per line)','Alice Example');await absent(page,'Download redacted package');
  await click(page,'Run de-identification review');await files(page,0,fixture.bad);await absent(page,'Download redacted package');
  r.assertions='own-field upload, literal/pattern redaction, separate sensitive originals, formula-safe headers/cells, settings and malformed upload invalidation';
}
async function screening(page){await check(page,/I reviewed mappings, units, criteria/);await click(page,'Run screening');await page.getByRole('button',{name:'Download complete review package (.zip)',exact:true}).waitFor();}
async function runRisk(page,dir,r){
  await files(page,0,fixture.risk);await select(page,'Safety domain for cardiac.custom.csv','eg');
  for(const [label,value] of [['Study ID column (optional)','protocol'],['USUBJID (required)','person'],['EGQTC (required)','interval'],['Result unit column (optional)','units']])await select(page,label,value);
  await check(page,/Confirm units for cardiac/);await screening(page);
  const z=zip(await download(page,'Download complete review package (.zip)',path.join(dir,'risk.zip')));
  assert.deepEqual(z.csv['signals.csv'].map(x=>[x.USUBJID,x.n_qtc]),[['001','0'],['002','1']]);
  assert.equal(z.files['inputs/cardiac.custom.csv'],fixture.risk.buffer.toString());assert.ok(z.files['source/risk_app.py']);
  r.theme=await themesAndPhone(page,dir,'Download complete review package (.zip)');await page.setViewportSize({width:1440,height:1000});
  await page.getByText('Screening thresholds and category cuts',{exact:true}).click();await fill(page,'QTC_ABS_MS','499');await absent(page,'Download complete review package (.zip)');
  assert.ok(await page.getByRole('button',{name:'Run screening',exact:true}).isDisabled(),'Changed criteria require fresh confirmation');
  await screening(page);const changed=zip(await download(page,'Download complete review package (.zip)',path.join(dir,'risk-499.zip')));
  assert.deepEqual(changed.csv['signals.csv'].map(x=>x.n_qtc),['1','1']);assert.equal(JSON.parse(changed.files['settings.json']).thresholds.QTC_ABS_MS,499);
  await files(page,0,fixture.bad);await absent(page,'Download complete review package (.zip)');r.assertions='arbitrary columns, units, QTc maximum/strict boundary, changed threshold calculation and reconfirmation, exact original/source export, malformed replacement';
}
async function runAnomaly(page,dir,r){
  await files(page,0,fixture.anomaly);
  for(const [label,value] of [['Participant column (required)','person'],['Time column (optional)','visit'],['Lab column (optional)','site'],['Study column (optional)','protocol'],['Unit column (optional)','units']])await select(page,label,value);
  await fill(page,'Unit for measurement (or unitless)','U/L');await screening(page);
  const z=zip(await download(page,'Download complete review package (.zip)',path.join(dir,'anomaly.zip')));
  assert.equal(+z.csv['drift.csv'][0].transport_distance,10);assert.equal(+z.csv['drift.csv'][0].n_ref,6);assert.equal(+z.csv['drift.csv'][0].n_cur,6);
  assert.deepEqual(z.csv['lab_drift.csv'].map(x=>[x.lab,+x.transport_distance]),[['A',0],['B',20]]);
  assert.deepEqual(z.csv['lab_compare.csv'].map(x=>[+x.n,+x.n_others,+x.transport_distance]),[[3,3,20],[3,3,20]]);
  assert.ok(z.csv['audit_log.csv'][0].drift_method.includes('not exact OT'));
  const inventory=JSON.parse(z.files['file_inventory.json']);for(const [name,sha] of Object.entries(inventory))assert.equal(z.sha256[name],sha);
  r.theme=await themesAndPhone(page,dir,'Download complete review package (.zip)');await page.setViewportSize({width:1440,height:1000});
  await select(page,'Current visit','0');await absent(page,'Download complete review package (.zip)');
  await check(page,/I reviewed mappings, units, criteria/);await click(page,'Run screening');await absent(page,'Download complete review package (.zip)');
  assert.ok((await page.locator('body').innerText()).includes('Choose a current visit strictly after the reference visit.'),'Identical paired visits rejected');
  await files(page,0,fixture.bad);await absent(page,'Download complete review package (.zip)');r.assertions='custom longitudinal mappings, complete matched pairs, six-person 10-unit and lab20-unit known answers, distinct participant counts, source/hash inventory, invalid pair and malformed replacement';
}
async function serve(){
  const mime={'.html':'text/html','.js':'text/javascript','.mjs':'text/javascript','.css':'text/css','.json':'application/json','.py':'text/plain','.csv':'text/csv','.whl':'application/zip','.wasm':'application/wasm'};
  const server=http.createServer((req,res)=>{try{let target=path.resolve(site,'.'+decodeURIComponent(new URL(req.url,'http://local').pathname));if(!target.startsWith(site+path.sep))throw Error('path');if(fs.statSync(target).isDirectory())target=path.join(target,'index.html');res.setHeader('Content-Type',mime[path.extname(target)]||'application/octet-stream');fs.createReadStream(target).pipe(res);}catch{res.statusCode=404;res.end('Not found');}});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));return server;
}
(async()=>{
  const server=process.env.TOOLKIT_PUBLIC_BASE?null:await serve();const base=process.env.TOOLKIT_PUBLIC_BASE||`http://127.0.0.1:${server.address().port}`;report.base=base;
  const browser=await chromium.launch({headless:true,...(process.env.CHROME_PATH?{executablePath:process.env.CHROME_PATH}:{})});
  try{for(const [app,run] of Object.entries({meddra:runCoding,phi:runPhi,risk:runRisk,anomaly:runAnomaly})){
    if(process.env.ECRF_QC_APP&&process.env.ECRF_QC_APP!==app)continue;
    const dir=path.join(out,app);fs.mkdirSync(dir,{recursive:true});const context=await browser.newContext({viewport:{width:1440,height:1000},colorScheme:'light',acceptDownloads:true});const page=await context.newPage();
    const r={app,errors:[],console_errors:[],requests:[]};report.apps.push(r);
    page.on('pageerror',e=>r.errors.push(e.message));page.on('console',m=>{if(m.type()==='error')r.console_errors.push(m.text());});
    page.on('request',req=>r.requests.push({url:req.url(),method:req.method(),bytes:req.postData()?.length||0,has_private_marker:(req.postData()||'').includes(privacyMarker)||req.url().includes(privacyMarker)}));
    try{
      const expected=fs.readFileSync(path.join(site,'ecrf_pipeline/docs/app',app+'_app.py'));
      const source=await page.request.get(base+'/ecrf_pipeline/docs/app/'+app+'_app.py');assert.equal(source.status(),200);
      r.source_sha256=digest(await source.body());assert.equal(r.source_sha256,digest(expected),'Served app matches site oracle');
      const canonical=path.join(site,'ecrf_pipeline',app+'_app.py');
      if(fs.existsSync(canonical))assert.equal(r.source_sha256,digest(fs.readFileSync(canonical)),'Generated app matches canonical source');
      await page.goto(base+'/ecrf_pipeline/docs/app/'+app+'.html');await page.getByRole('button',{name:'Load synthetic example',exact:true}).waitFor({timeout:180000});await settled(page);
      assert.equal(await page.getByRole('button',{name:/Download.*package/}).count(),0,'Blank workspace has no computed package');await page.screenshot({path:path.join(dir,'blank.png'),fullPage:true});
      await click(page,'Load synthetic example');assert.ok((await page.locator('body').innerText()).includes(app==='meddra'?'Map study fields':app==='phi'?'Choose fields':'Map'));
      await click(page,'Reset workspace');assert.equal(await page.getByRole('button',{name:/Run coding|Run de-identification|Run screening/}).count(),0,'Example reset is blank');
      await run(page,dir,r);
      await click(page,'Reset workspace');assert.equal(await page.getByRole('button',{name:/Run coding|Run de-identification|Run screening|Download.*package/}).count(),0,'Final reset removes inputs and results');
      await page.setViewportSize({width:390,height:844});await page.getByRole('button',{name:'Load synthetic example',exact:true}).scrollIntoViewIfNeeded();await page.waitForTimeout(250);await page.screenshot({path:path.join(dir,'phone-reset.png'),fullPage:true});
      await click(page,'Load synthetic example');assert.ok(await page.getByRole('button',{name:/Run coding|Run de-identification|Run screening/}).count(),'Phone form remains interactive');
      assert.equal(await page.evaluate(()=>globalThis.ecrfXSS||0),0);assert.deepEqual(r.errors,[]);
      // stlite 1.12.0 probes its deliberately invalid media placeholder before
      // resolving the in-worker blob. CSP blocks that probe; successful ZIP
      // downloads above independently prove the real download path. Retain each
      // exact diagnostic; do not hide other fetch or console failures.
      const placeholder=r.console_errors.some(x=>/^Connecting to 'https:\/\/stlite\.invalid\/.*\/media\/[a-f0-9]+\.(zip|csv)' violates the following Content Security Policy directive:/.test(x));
      r.expected_placeholder_diagnostics=r.console_errors.filter(x=>/^Connecting to 'https:\/\/stlite\.invalid\/.*\/media\/[a-f0-9]+\.(zip|csv)' violates the following Content Security Policy directive:/.test(x)||/^Fetch API cannot load https:\/\/stlite\.invalid\/.*\/media\/[a-f0-9]+\.(zip|csv)\. Refused to connect because it violates the document's Content Security Policy\.$/.test(x)||(placeholder&&x==='Client Error: Download Button fetch error - Failed to fetch'));
      r.unexpected_console_errors=r.console_errors.filter(x=>!r.expected_placeholder_diagnostics.includes(x));assert.deepEqual(r.unexpected_console_errors,[]);
      assert.ok(r.requests.every(q=>!q.has_private_marker),'Study content stays off network');assert.ok(r.requests.every(q=>['GET','HEAD'].includes(q.method)),'No study upload requests');
      assert.ok(r.requests.every(q=>{const u=new URL(q.url);return u.origin===new URL(base).origin||u.hostname==='cdn.jsdelivr.net'||['blob:','data:'].includes(u.protocol);}), 'Only site/CDN runtime assets and local blobs requested');
      r.downloads=fs.readdirSync(dir).filter(n=>n.endsWith('.zip')).length;r.passed=true;console.log(app+' PASS');
    }catch(e){r.error=e.stack;report.errors.push(app+': '+e.message);try{r.body=await page.locator('body').innerText();await page.screenshot({path:path.join(dir,'failure.png'),fullPage:true});}catch{}console.error(app+' FAIL '+e.message);}
    finally{fs.writeFileSync(path.join(dir,'report.json'),JSON.stringify(r,null,2));await context.close();}
  }}finally{await browser.close();if(server)await new Promise(resolve=>server.close(resolve));report.finished=new Date().toISOString();report.passed=report.errors.length===0;fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));}
  if(!report.passed)process.exitCode=1;
})().catch(e=>{report.errors.push(e.stack);fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));console.error(e);process.exitCode=1;});
