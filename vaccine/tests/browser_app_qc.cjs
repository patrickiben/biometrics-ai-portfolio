/* Real exported Shinylive/webR vaccine application QC; synthetic inputs only.
 * NODE_PATH=/path/to/playwright/node_modules CHROME_PATH=/path/to/chrome \
 * QA_OUTPUT_DIR=/path/to/evidence node vaccine/tests/browser_app_qc.cjs /path/to/built/site
 * Starts a static server (never native Shiny). Rscript supplies an independent native
 * same-core comparison; all app interaction and result generation happens in webR.
 */
'use strict';
const {chromium}=require('playwright');
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os'),http=require('node:http'),cp=require('node:child_process'),crypto=require('node:crypto');
const {checkDownloadedReportThemes}=require('../../toolkit_launcher/tests/report_theme_qc.cjs');
const repo=path.resolve(__dirname,'../..'),root=path.resolve(process.env.VACCINE_REVIEWED_SOURCE_DIR||repo),site=path.resolve(process.argv[2]||'_site');
const remoteBase=(process.env.TOOLKIT_PUBLIC_BASE||'').replace(/\/$/,'');
if(remoteBase&&!remoteBase.startsWith('https://'))throw Error('Live QC requires an HTTPS public base URL.');
const evidence=process.env.QA_OUTPUT_DIR||fs.mkdtempSync(path.join(os.tmpdir(),'vaccine-browser-qc-'));
const out=path.join(evidence,'browser-app');fs.mkdirSync(out,{recursive:true});
const prefix='/biometrics-ai-portfolio';
const report={started_at:new Date().toISOString(),site,reviewed_source:root,public_base:remoteBase||null,scenarios:[],screenshots:[],errors:[],console_errors:[],network_requests:[],server_requests:[],downloads:[],native_parity:[],numeric_tolerance:'absolute error <= 1e-9 * max(1, abs(native value)); missingness and nonnumeric values match exactly',scope:'Actual exported Shinylive/webR with synthetic local CSVs. Native R is used only as a comparison oracle.'};
let browser,server,page,frame,base;
const ids=['immunogenicity','fold_rise','response','titer_plot','reactogenicity','diary_profile'];
const marker='BROWSER-QC-PRIVATE-SYNTHETIC';
const fields={participants:['USUBJID','ARM','IMMFL','SAFEFL'],titers:['USUBJID','ASSAY','ANTIGEN','UNIT','VISIT','AVAL','QUALIFIER','LLOQ','ULOQ'],doses:['USUBJID','DOSE'],diary:['USUBJID','DOSE','DAY','SYMPTOM','GRADE']};
const cfg={study_id:'BROWSER-VAX-QC',outputs:ids,assay:'Assay',antigen:'Antigen',unit:'AU/mL',baseline_visit:'Baseline',followup_visits:'Post',confidence:.95,blq_policy:'exclude',alq_policy:'exclude',response_rule:'conditional',response_threshold:40,fold_threshold:4,baseline_threshold:20,dose_labels:'Dose 1\nDose 2',symptoms:'Pain',day_start:0,day_end:2,max_grade:3,react_denominator:'complete'};
function fixture(){
 const participants=['A1','A2','A3','A4','B1','B2'].map(id=>({USUBJID:marker+'-'+id+(id==='A1'?"';%put VAX_QC_TEXT; <script>window.VAX_QC_EXEC=1</script>":''),ARM:id[0],IMMFL:'Y',SAFEFL:'Y'}));
 const before=[10,20,40,80,5,5],after=[40,40,160,null,10,10];
 const titers=participants.flatMap((p,i)=>['Baseline','Post'].map((VISIT,j)=>({USUBJID:p.USUBJID,ASSAY:'Assay',ANTIGEN:'Antigen',UNIT:'AU/mL',VISIT,AVAL:j?after[i]:before[i],QUALIFIER:j&&after[i]===null?'MISSING':'EXACT',LLOQ:2,ULOQ:200})));
 const doses=participants.map(p=>({USUBJID:p.USUBJID,DOSE:'Dose 1'})).concat([{USUBJID:participants[0].USUBJID,DOSE:'Dose 2'}]);
 const diary=participants.flatMap((p,i)=>[0,1,2].filter(day=>i!==3&&!(i===1&&day===2)).map(DAY=>({USUBJID:p.USUBJID,DOSE:'Dose 1',DAY,SYMPTOM:'Pain',GRADE:i===0?DAY:i===1?(DAY===0?1:null):0}))).concat([0,1,2].map(DAY=>({USUBJID:participants[0].USUBJID,DOSE:'Dose 2',DAY,SYMPTOM:'Pain',GRADE:0})));
 return {participants,titers,doses,diary};
}
const clone=x=>JSON.parse(JSON.stringify(x));
function csv(rows,columns){const quote=x=>x===null||x===undefined?'':'"'+String(x).replaceAll('"','""')+'"';return columns.map(quote).join(',')+'\n'+rows.map(row=>columns.map(key=>quote(row[key])).join(',')).join('\n')+(rows.length?'\n':'');}
function writeFixture(name,data,mapping={}){const dir=path.join(out,'inputs',name);fs.mkdirSync(dir,{recursive:true});const files={};for(const [slot,rows]of Object.entries(data)){const aliases=mapping[slot]||{};files[slot]=path.join(dir,slot+'.csv');fs.writeFileSync(files[slot],csv(rows.map(row=>Object.fromEntries(Object.entries(row).map(([key,value])=>[aliases[key]||key,value]))),fields[slot].map(key=>aliases[key]||key)));}return files;}
async function scenario(name,fn){const started=Date.now();await fn();report.scenarios.push({name,passed:true,elapsed_ms:Date.now()-started});console.log('PASS '+name);}
async function startServer(){
 assert.ok(fs.existsSync(path.join(site,'apps/vaccine/app.json')),'Export vaccine app before running browser QC');
 const bundle=fs.readFileSync(path.join(site,'apps/vaccine/app.json'));report.bundle_sha256=crypto.createHash('sha256').update(bundle).digest('hex');const bundled=JSON.parse(bundle);report.reviewed_source_hashes={};
 if(remoteBase){const response=await fetch(remoteBase+'/apps/vaccine/app.json');assert.equal(response.status,200);assert.deepEqual(Buffer.from(await response.arrayBuffer()),bundle,'Live app bundle equals reviewed export');}
 for(const [name,relative]of Object.entries({'app.R':'vaccine/shiny/app.R','vaccine-ui.js':'vaccine/shiny/vaccine-ui.js','vaccine-ui.css':'vaccine/shiny/vaccine-ui.css','portfolio_app.R':'apps/_shared/portfolio_app.R','vaccine/analysis.R':'vaccine/analysis.R','vaccine/browser.R':'vaccine/browser.R','vaccine/reference.sas':'vaccine/reference.sas','toolkit_launcher/analysis_runner.R':'toolkit_launcher/analysis_runner.R','assets/theme/tokens.css':'assets/theme/tokens.css'})){
  const file=bundled.find(x=>x.name===name);assert.ok(file,'Export contains '+name);const source=fs.readFileSync(path.join(root,relative)),hash=crypto.createHash('sha256').update(source).digest('hex');assert.equal(crypto.createHash('sha256').update(Buffer.from(file.content,'utf8')).digest('hex'),hash,'Export uses current reviewed '+relative);report.reviewed_source_hashes[relative]=hash;
 }
 if(remoteBase){base=remoteBase;return;}
 const types={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.mjs':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.json':'application/json','.wasm':'application/wasm','.png':'image/png','.svg':'image/svg+xml','.woff2':'font/woff2','.gz':'application/gzip','.tgz':'application/gzip','.data':'application/octet-stream'};
 server=http.createServer((req,res)=>{const url=new URL(req.url,'http://127.0.0.1');const entry={method:req.method,path:url.pathname,query:url.search,status:null,body_bytes:0};report.server_requests.push(entry);req.on('data',b=>entry.body_bytes+=b.length);
  try{if(!['GET','HEAD'].includes(req.method)){entry.status=405;res.writeHead(405);res.end('Static site: uploads are not accepted');return;}assert.ok(url.pathname.startsWith(prefix+'/'));let file=path.resolve(site,'.'+decodeURIComponent(url.pathname.slice(prefix.length)));assert.ok(file===site||file.startsWith(site+path.sep));if(fs.statSync(file).isDirectory())file=path.join(file,'index.html');const st=fs.statSync(file);assert.ok(st.isFile());entry.status=200;entry.response_bytes=req.method==='HEAD'?0:st.size;res.writeHead(200,{'Content-Type':types[path.extname(file)]||'application/octet-stream','Content-Length':st.size,'Cache-Control':'no-cache'});if(req.method==='HEAD')res.end();else fs.createReadStream(file).pipe(res);}catch{entry.status=404;res.writeHead(404);res.end('Not found');}});
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));base='http://127.0.0.1:'+server.address().port+prefix;
}
async function ready(){await page.waitForFunction(()=>window.launchStatus?.ready,null,{timeout:240000});frame=page.frames().find(f=>/\/app_[^/]+\//.test(f.url()));assert.ok(frame,'Exported app iframe exists');await frame.locator('#load_example').waitFor({state:'visible',timeout:30000});await settle();}
async function settle(){await page.waitForTimeout(100);await frame.waitForFunction(()=>!document.documentElement.classList.contains('shiny-busy'),null,{timeout:60000});await page.waitForTimeout(150);}
async function nav(value){await frame.locator('.nav-link[data-value="'+value+'"]').click();await frame.locator('.nav-link.active[data-value="'+value+'"]').waitFor({state:'visible'});await settle();}
function fileInput(slot){return frame.locator('#upload_'+slot+' input[type=file]');}
async function upload(slot,file){const input=fileInput(slot),before=await input.getAttribute('id'),started=Date.now();await input.setInputFiles(file);try{await frame.waitForFunction(({slot,before})=>{const status=document.querySelector('#input_status_'+slot+' .vax-input-summary');return status?.dataset.pending==='false'&&status.dataset.loaded==='true'&&Number(status.dataset.uploadId.split('_').pop())>Number(before.split('_').pop());},{slot,before},{timeout:120000});}catch(error){report.upload_failure={slot,selected_id:before,...await frame.evaluate(slot=>{const node=document.querySelector('#input_status_'+slot+' .vax-input-summary');return{status:node?{...node.dataset}:null,status_text:node?.textContent,current_id:document.querySelector('#upload_'+slot+' input[type=file]')?.id,bound_values:Object.fromEntries(Object.entries(window.Shiny?.shinyapp?.$inputValues||{}).filter(([key])=>key==='upload_started'||key==='upload_failed'||key.startsWith('file_')))};},slot)};throw error;}await settle();report.uploads=report.uploads||[];report.uploads.push({slot,file:path.basename(file),bytes:fs.statSync(file).size,input_id:before,accepted_generation:await frame.locator('#input_status_'+slot+' .vax-input-summary').getAttribute('data-upload-id'),elapsed_ms:Date.now()-started});}
async function loadExample(){await frame.locator('#load_example').click();await frame.locator('.nav-link.active[data-value="review"]').waitFor({state:'visible'});await frame.waitForFunction(()=>document.querySelector('.vax-state-count')?.textContent.includes('4 of 4'));await settle();}
async function setValue(id,value){const el=frame.locator('#'+id);await el.waitFor({state:'attached'});const tag=await el.evaluate(e=>e.tagName);if(tag==='SELECT')await el.selectOption(String(value));else if(await el.getAttribute('type')==='checkbox')await el.setChecked(!!value);else{await el.fill(String(value));await el.dispatchEvent('change');}await settle();}
async function stableSettings(){let previous='',stable=0;const end=Date.now()+20000;while(Date.now()<end){await settle();const snapshot=await frame.evaluate(()=>JSON.stringify({busy:document.documentElement.classList.contains('shiny-busy'),fields:[...document.querySelectorAll('.vax-setup input,.vax-setup select,.vax-setup textarea')].map(e=>[e.id,e.value,e.checked])}));if(snapshot===previous&&!JSON.parse(snapshot).busy)stable++;else stable=0;if(stable>=2)return;previous=snapshot;await page.waitForTimeout(400);}throw Error('Form values did not become stable before review');}
async function state(){return frame.locator('#analysis_state').getAttribute('data-state');}
async function expectState(wanted,timeout=120000){await frame.waitForFunction(value=>document.querySelector('#analysis_state')?.dataset.state===value,wanted,{timeout});}
async function shot(name){const file=name+'.png';await page.screenshot({path:path.join(out,file),fullPage:false});report.screenshots.push(file);}
async function download(id,name){const pending=page.waitForEvent('download',{timeout:60000});await frame.locator('#'+id).click();const item=await pending;const dest=path.join(out,'downloads',name||item.suggestedFilename());fs.mkdirSync(path.dirname(dest),{recursive:true});await item.saveAs(dest);assert.equal(await item.failure(),null);report.downloads.push({name:item.suggestedFilename(),path:path.relative(out,dest),bytes:fs.statSync(dest).size});return dest;}
function readCsv(file){return JSON.parse(cp.execFileSync(process.env.TOOLKIT_PYTHON||'python3',['-c','import csv,json,sys; print(json.dumps(list(csv.DictReader(open(sys.argv[1],newline="",encoding="utf-8-sig")))))',file],{encoding:'utf8',maxBuffer:64*1024*1024}));}
function near(actual,expected,label){assert.ok(actual!==''&&actual!==null&&Number.isFinite(Number(actual))&&Math.abs(Number(actual)-expected)<=1e-9*Math.max(1,Math.abs(expected)),label+': '+actual+' != '+expected);}
function cell(rows,criteria){const found=rows.filter(row=>Object.entries(criteria).every(([key,value])=>String(row[key])===String(value)));assert.equal(found.length,1,'Unique row '+JSON.stringify(criteria));return found[0];}
function knownAnswers(tables,policy='complete'){
 let x=cell(tables['immunogenicity/01'],{ARM:'A',VISIT:'Post'});assert.equal(Number(x.n_population),4);assert.equal(Number(x.n_evaluable),3);assert.equal(Number(x.n_not_evaluable),1);near(x.geometric_mean,Math.cbrt(40*40*160),'GMT');
 x=cell(tables['fold_rise/01'],{ARM:'A',VISIT:'Post'});assert.equal(Number(x.n_paired),3);assert.equal(Number(x.n_unpaired),1);near(x.geometric_mean_fold_rise,Math.cbrt(4*2*4),'Paired GMFR');
 x=cell(tables['response/01'],{ARM:'A',VISIT:'Post'});assert.equal(Number(x.n_responders),2);assert.equal(Number(x.n_evaluable),3);near(x.percent,200/3,'Conditional response at equality');
 x=cell(tables['reactogenicity/01'],{ARM:'A',DOSE:'Dose 1',SYMPTOM:'Pain'});assert.equal(Number(x.n_dosed),4);assert.equal(Number(x.n_complete),2);assert.equal(Number(x.n_partial),1);assert.equal(Number(x.n_unassessed),1);assert.equal(Number(x.n_partial_positive),1);assert.equal(Number(x.n_missing_day_assessments),5);near(x.percent,policy==='complete'?50:200/3,'Diary denominator policy');
 x=cell(tables['reactogenicity/01'],{ARM:'B',DOSE:'Dose 1',SYMPTOM:'Pain'});assert.equal(Number(x.n_reaction),0);assert.equal(Number(x.percent),0);near(x.upper_percent,100*(1-Math.sqrt(.025)),'Zero-event exact CI');
 const daily=Object.values(tables).find(rows=>rows.length&&'n_assessed'in rows[0]&&'DAY'in rows[0]);assert.ok(daily,'Complete daily table present');for(const [DAY,n]of [[0,3],[1,2],[2,2]])assert.equal(Number(cell(daily,{ARM:'A',DOSE:'Dose 1',SYMPTOM:'Pain',DAY}).n_assessed),n);
}
function nativeExpected(name,data,settings){
 const input=path.join(out,'native-'+name+'-input.json'),target=path.join(out,'native-'+name+'.json');
 fs.writeFileSync(input,JSON.stringify({data,settings,root,target,fields}));
 const code=`args<-commandArgs(TRUE);b<-jsonlite::read_json(args[[1]],simplifyVector=TRUE);source(file.path(b$root,'vaccine','analysis.R'));cfg<-b$settings;for(k in c('followup_visits','dose_labels','symptoms'))cfg[[k]]<-strsplit(cfg[[k]],'\\n',fixed=TRUE)[[1]];for(slot in names(b$data))if(!is.data.frame(b$data[[slot]]))b$data[[slot]]<-as.data.frame(setNames(rep(list(character()),length(b$fields[[slot]])),b$fields[[slot]]));p<-vaccine_prepare(b$data,cfg);result<-list();for(id in cfg$outputs){o<-vaccine_output(id,p,cfg);for(i in seq_along(o$components)){d<-o$components[[i]]$value;if(is.data.frame(d)){key<-sprintf('outputs/%s/component-%02d.csv',id,i);result[[key]]<-list(columns=names(d),types=as.list(vapply(d,function(x)if(is.numeric(x))'numeric'else if(is.logical(x))'logical'else 'character','')),rows=d)}}};jsonlite::write_json(result,b$target,auto_unbox=TRUE,dataframe='rows',na='null',digits=16,pretty=TRUE)`;
 cp.execFileSync(process.env.RSCRIPT||'Rscript',['-e',code,input],{cwd:root,encoding:'utf8',timeout:120000});return JSON.parse(fs.readFileSync(target,'utf8'));
}
async function setup(settings,files,mapping={}){
 await nav('study');for(const key of ['study_id','confidence'])await setValue(key,settings[key]);for(const [key,fallback]of [['yes_value','Y'],['no_value','N']])await setValue(key,settings[key]??fallback);
 for(const id of ids)await frame.locator('#outputs input[value="'+id+'"]').setChecked(settings.outputs.includes(id));await settle();
 await nav('inputs');
 for(const [slot,file]of Object.entries(files)){await upload(slot,file);await frame.locator('#map_'+slot+'_USUBJID').waitFor({state:'attached'});for(const [canonical,alias]of Object.entries(mapping[slot]||{}))await setValue('map_'+slot+'_'+canonical,alias);}
 await nav('assay');for(const key of ['assay','antigen','unit','baseline_visit','followup_visits','blq_policy','alq_policy','response_rule','response_threshold','fold_threshold','baseline_threshold'])await setValue(key,settings[key]);
 for(const [key,fallback]of [['qualifier_exact','EXACT'],['qualifier_blq','BLQ'],['qualifier_alq','ALQ'],['qualifier_missing','MISSING']])await setValue(key,settings[key]??fallback);
 await nav('diary');for(const key of ['dose_labels','symptoms','day_start','day_end','max_grade','react_denominator'])await setValue(key,settings[key]);
}
async function confirmAndRun(count=6,timeout=120000){
 await nav('review');await stableSettings();for(const id of ['visits_confirmed','diary_confirmed','review_confirmed'])await setValue(id,true);await stableSettings();for(const id of ['visits_confirmed','diary_confirmed','review_confirmed'])assert.equal(await frame.locator('#'+id).isChecked(),true,'Review remained checked after stable settings: '+id);
 await frame.locator('#validate_setup').click();await settle();await frame.waitForFunction(()=>['ready','invalid','error'].includes(document.querySelector('#analysis_state')?.dataset.state),null,{timeout:120000});assert.equal(await state(),'ready',await frame.locator('#validation_messages').innerText());await frame.locator('#run_analysis').click();await expectState('succeeded',timeout);await nav('results');
 assert.equal(await frame.locator('#result_summary').getAttribute('data-output-count'),String(count));assert.equal(await frame.locator('.shiny-output-error:not(.shiny-output-error-validation)').count(),0);
}
async function collectTables(name,expected){
 const options=await frame.locator('#download_choice option').evaluateAll(nodes=>nodes.map(n=>({value:n.value,label:n.textContent})));const tables={};
 const zip=await download('download_bundle',name+'.zip'),directory=path.join(out,'extracted',name);
 const inventory=JSON.parse(cp.execFileSync(process.env.TOOLKIT_PYTHON||'python3',['-c',`import pathlib,sys,zipfile,json
with zipfile.ZipFile(sys.argv[1]) as z:
 assert z.testzip() is None
 names=z.namelist()
 assert len(names)==len(set(names))
 for n in names:
  p=pathlib.PurePosixPath(n)
  assert not p.is_absolute() and '..' not in p.parts and '\\\\' not in n
  assert not any(x in p.parts for x in ('.git','.biostat-toolkit','toolkit_configuration','template_inputs'))
 z.extractall(sys.argv[2])
 print(json.dumps(names))`,zip,directory],{encoding:'utf8'}));
 report.downloads[report.downloads.length-1].zip_members=inventory;
 for(const [relative,oracle]of Object.entries(expected)){
  assert.ok(options.some(o=>o.value===relative),'Download available '+relative);assert.ok(inventory.includes(relative),'ZIP contains '+relative);const file=path.join(directory,relative),rows=readCsv(file);assert.equal(rows.length,oracle.rows.length,'Native row count '+relative);
  if(rows.length)assert.deepEqual(Object.keys(rows[0]),oracle.columns,'Native columns '+relative);
  for(let row=0;row<rows.length;row++)for(const column of oracle.columns){const got=rows[row][column],want=oracle.rows[row][column],where=relative+' row '+row+' '+column;if(want===null)assert.equal(got,'',where+' missingness');else if(oracle.types[column]==='numeric')near(got,want,where);else if(oracle.types[column]==='logical')assert.equal(got.toUpperCase(),String(want).toUpperCase(),where);else assert.equal(got,String(want),where);}
  const m=relative.match(/^outputs\/([^/]+)\/component-(\d+)\.csv$/);assert.ok(m,relative);tables[m[1]+'/'+m[2]]=rows;report.native_parity.push({case:name,file:relative,rows:rows.length,columns:oracle.columns.length,passed:true});
 }
 return {tables,options,directory,inventory};
}
async function unavailable(id){const locator=frame.locator('#'+id);return !await locator.count()||!await locator.isVisible()||!await locator.isEnabled();}
async function rejectSetup(pattern){
 await nav('review');for(const id of ['visits_confirmed','diary_confirmed','review_confirmed'])await setValue(id,true);await frame.locator('#validate_setup').click();await expectState('invalid');assert.match(await frame.locator('#validation_messages').innerText(),pattern);assert.equal(await unavailable('run_analysis'),true);assert.equal(await unavailable('download_report'),true);
}
async function noStaleResults(){assert.notEqual(await state(),'succeeded');await nav('results');const summary=frame.locator('#result_summary');assert.equal(await summary.count()?await summary.getAttribute('data-run-id'):null,null);assert.equal(await unavailable('download_report'),true);assert.equal(await unavailable('download_bundle'),true);}

(async()=>{
 await startServer();browser=await chromium.launch({headless:true,...(process.env.CHROME_PATH?{executablePath:process.env.CHROME_PATH}:{})});
 const context=await browser.newContext({viewport:{width:1440,height:1000},acceptDownloads:true});page=await context.newPage();page.setDefaultTimeout(30000);
 const requests=new WeakMap();context.on('request',request=>{const entry={url:request.url(),method:request.method(),body_bytes:request.postDataBuffer()?.length||0,contains_synthetic_marker:(request.url()+(request.postData()||'')).includes(marker)};requests.set(request,entry);report.network_requests.push(entry);});context.on('response',response=>{const entry=requests.get(response.request());if(entry){entry.status=response.status();entry.from_service_worker=response.fromServiceWorker();}});
 page.on('pageerror',error=>report.errors.push(error.message));page.on('console',message=>{if(message.type()==='error')report.console_errors.push(message.text());});
 await scenario('Exported webR app starts empty without a native R or toolkit server',async()=>{
  const started=Date.now();await page.goto(base+'/apps/vaccine/',{waitUntil:'domcontentloaded'});await ready();report.initial_readiness={elapsed_ms:Date.now()-started,static_response_bytes:report.server_requests.reduce((n,r)=>n+(r.response_bytes||0),0),launch:await page.evaluate(()=>window.launchStatus?.times||null)};assert.equal(await state(),'empty');assert.equal(await unavailable('download_bundle'),true);
  assert.match(await frame.locator('body').innerText(),/browser/i);await shot('initial-desktop');
 });
 await scenario('Synthetic example loads deliberately and requires review before execution',async()=>{
  await loadExample();await nav('inputs');await setValue('map_participants_ARM','USUBJID');await setValue('map_participants_USUBJID','ARM');await loadExample();await nav('inputs');assert.equal(await frame.locator('#map_participants_ARM').inputValue(),'ARM','Example resets prior source mapping');assert.equal(await frame.locator('#map_participants_USUBJID').inputValue(),'USUBJID','Example resets prior ID mapping');await nav('review');
  for(const id of ['visits_confirmed','diary_confirmed','review_confirmed'])assert.equal(await frame.locator('#'+id).isChecked(),false,id+' example did not approve itself');
  await frame.locator('#validate_setup').click();await expectState('invalid');assert.match(await frame.locator('#validation_messages').innerText(),/confirm|review/i);
  await confirmAndRun();assert.equal(await frame.locator('#result_output option').count(),6);await shot('example-six-outputs');
 });
 const data=fixture(),mapping={participants:{USUBJID:'Participant ID',ARM:'Treatment group'}},files=writeFixture('known',data,mapping);
 let baseline;
 await scenario('Real CSV uploads and renamed-column mapping produce six known-answer outputs with native parity',async()=>{
  await setup(cfg,files,mapping);await noStaleResults();await confirmAndRun();baseline=await collectTables('known',nativeExpected('known',data,cfg));knownAnswers(baseline.tables);
  assert.deepEqual((await frame.locator('#result_output option').evaluateAll(ns=>ns.map(n=>n.value))).sort(),ids.slice().sort());
  for(const id of ids){await setValue('result_output',id);await settle();assert.ok((await frame.locator('#result_component option').count())>=2,id+' retains every component');}
 });
 await scenario('All downloadable files match bundle bytes; report, native SAS reference and plots are real artifacts',async()=>{
  for(const {value}of baseline.options){if(!value)continue;assert.ok(baseline.inventory.includes(value),'Bundle includes downloadable '+value);await setValue('download_choice',value);const file=await download('download_file',path.join('individual',value));assert.deepEqual(fs.readFileSync(file),fs.readFileSync(path.join(baseline.directory,value)),'Individual matches ZIP '+value);}
  const reportFile=await download('download_report','direct-report.html');assert.match(fs.readFileSync(reportFile,'utf8'),/<!doctype html|<html/i);assert.match(fs.readFileSync(reportFile,'utf8'),/missing|incomplete/i);
  const profileFile=await download('download_profile','direct-profile.json'),profile=JSON.parse(fs.readFileSync(profileFile,'utf8'));assert.ok(!JSON.stringify(profile).includes(marker),'Settings profile excludes participant records');
  const sasFile=await download('download_sas','direct-reference.sas'),sas=fs.readFileSync(sasFile,'utf8');assert.match(sas,/unexecuted|not executed/i);assert.match(sas,/vaccine|immunogenicity/i);
  assert.ok(!sas.includes('%put VAX_QC_TEXT;'),'Uploaded text cannot become native SAS macro code');assert.ok(sas.includes(Buffer.from('%put VAX_QC_TEXT;').toString('hex')),'SAS retains uploaded text as a hex literal');
  for(const file of baseline.inventory.filter(p=>p.endsWith('.html')))assert.ok(!fs.readFileSync(path.join(baseline.directory,file),'utf8').includes('<script>window.VAX_QC_EXEC=1</script>'),'Uploaded text escaped in '+file);
  await setValue('result_output','reactogenicity');await setValue('result_component','3');await settle();assert.equal(await frame.evaluate(()=>typeof window.VAX_QC_EXEC),'undefined','Uploaded markup remains data in browser table');
  const figures=baseline.inventory.filter(p=>/\.(png|svg|pdf)$/i.test(p));assert.ok(figures.length>=3,'Actual titer and two dose figures exported');for(const file of figures){const b=fs.readFileSync(path.join(baseline.directory,file));assert.ok(b.length>200,'Nonempty figure '+file);if(file.endsWith('.png'))assert.equal(b.subarray(1,4).toString(),'PNG');else if(file.endsWith('.pdf'))assert.equal(b.subarray(0,4).toString(),'%PDF');else assert.match(b.toString(),/<svg/);}
  const manifest=JSON.parse(fs.readFileSync(path.join(baseline.directory,'output_manifest.json'))),qc=JSON.parse(fs.readFileSync(path.join(baseline.directory,'qc.json')));assert.equal(manifest.status,'succeeded');assert.equal(manifest.approved,false);assert.equal(qc.passed,true);assert.equal(qc.approved,false);assert.deepEqual(manifest.outputs.map(o=>o.id).sort(),ids.slice().sort());
  for(const item of readCsv(path.join(baseline.directory,'file_inventory.csv')))assert.equal(crypto.createHash('md5').update(fs.readFileSync(path.join(baseline.directory,item.file))).digest('hex'),item.md5,'Export inventory '+item.file);
  // Shinylive's R loader uses writeLines() on each app.json text scalar, adding
  // exactly one LF. Preserve the executed runtime bytes and reject every other
  // difference; do not silently trim or normalize arbitrary source changes.
  const loader=fs.readFileSync(path.join(site,'shinylive/shinylive.js'),'utf8'),buildSource=fs.readFileSync(path.join(root,'.github/pages/build_site.R'),'utf8'),loaderCall='writeLines(files[[name]], filename, useBytes = TRUE)';assert.ok(loader.includes(loaderCall));
  report.runtime_loader={shinylive_package:buildSource.match(/SHINYLIVE\s*<-\s*"([^"]+)"/)[1],assets_version:buildSource.match(/ASSETS\s*<-\s*"([^"]+)"/)[1],file:'shinylive/shinylive.js',sha256:crypto.createHash('sha256').update(loader).digest('hex'),line:loader.slice(0,loader.indexOf(loaderCall)).split('\n').length,source:loaderCall};
  report.runtime_source_preservation=[];
  for(const relative of ['vaccine/analysis.R','vaccine/browser.R','vaccine/reference.sas','toolkit_launcher/analysis_runner.R','assets/theme/tokens.css']){const original=fs.readFileSync(path.join(root,relative)),actual=fs.readFileSync(path.join(baseline.directory,relative));assert.deepEqual(actual,Buffer.concat([original,Buffer.from('\n')]),'Preserved executed source '+relative);report.runtime_source_preservation.push({file:relative,reviewed_sha256:crypto.createHash('sha256').update(original).digest('hex'),executed_sha256:crypto.createHash('sha256').update(actual).digest('hex'),loader_transform:'Shinylive writeLines appends exactly one LF; no other difference'});}
  cp.execFileSync(process.env.TOOLKIT_PYTHON||'python3',['-c',`from html.parser import HTMLParser
from pathlib import Path
import sys,urllib.parse
root=Path(sys.argv[1]).resolve()
class Links(HTMLParser):
 def handle_starttag(self,tag,attrs):
  for key,value in attrs:
   if key in ('href','src') and value and not value.startswith(('#','data:','http:','https:','blob:')):
    target=(self.file.parent/urllib.parse.unquote(value.split('#')[0].split('?')[0])).resolve()
    assert target.is_relative_to(root) and target.exists(), (self.file,value)
for file in root.rglob('*.html'):
 p=Links();p.file=file;p.feed(file.read_text(encoding='utf8'))`,baseline.directory],{encoding:'utf8'});
 });
 await scenario('Setting changes invalidate exports and observed-diary policy changes its stated denominator',async()=>{
  await nav('diary');await setValue('react_denominator','observed');await noStaleResults();await confirmAndRun();const settings={...cfg,react_denominator:'observed'};const result=await collectTables('observed',nativeExpected('observed',data,settings));knownAnswers(result.tables,'observed');assert.match(JSON.stringify(result.tables['reactogenicity/01']),/observed/i);
 });
 await scenario('Oversized replacement clears the old feed and cannot reuse a completed analysis',async()=>{
  const file=path.join(out,'inputs','oversized.csv'),fd=fs.openSync(file,'w');fs.ftruncateSync(fd,16*1024*1024+1);fs.closeSync(fd);await nav('inputs');await fileInput('participants').setInputFiles(file);await settle();await expectState('invalid');assert.match(await frame.locator('#analysis_state').innerText(),/16 MiB|16 MB|maximum|too large/i);assert.match(await frame.locator('#input_status_participants').innerText(),/No data|missing/i);await noStaleResults();await nav('review');assert.equal(await unavailable('run_analysis'),true);
  await nav('inputs');await upload('participants',files.participants);await setValue('map_participants_USUBJID','Participant ID');await setValue('map_participants_ARM','Treatment group');await stableSettings();await confirmAndRun();
 });
 await scenario('Immediate concurrent file selections each complete once and produce the current results',async()=>{
  await nav('inputs');await Promise.all([upload('participants',files.participants),upload('titers',files.titers)]);await noStaleResults();await confirmAndRun();const settings={...cfg,react_denominator:'observed'};const result=await collectTables('concurrent',nativeExpected('concurrent',data,settings));knownAnswers(result.tables,'observed');
 });
 await scenario('Invalid column mappings, units, duplicates, numeric inputs and orphan doses block analysis',async()=>{
  await nav('inputs');await setValue('map_participants_USUBJID','Treatment group');await rejectSetup(/duplicat|mapping|same source|distinct source/i);await nav('inputs');await setValue('map_participants_USUBJID','Participant ID');
  const challenges=[
   ['mixed-unit','titers',rows=>{rows[0].UNIT='different unit';},/unit/i],
   ['duplicate','titers',rows=>{rows.push(clone(rows[0]));},/duplicate/i],
   ['nonpositive','titers',rows=>{rows[0].AVAL=0;},/positive|quantification/i],
   ['censored-payload','titers',rows=>{rows[0].QUALIFIER='BLQ';},/AVAL|blank|censor/i],
   ['population-flag','participants',rows=>{rows[0].IMMFL='Unknown';},/population|configured/i],
   ['orphan-dose','diary',rows=>{rows[0].DOSE='Not administered';},/orphan|dose/i],
   ['grade','diary',rows=>{rows[0].GRADE=1.5;},/whole|integer/i]
  ];
  for(const [name,slot,mutate,pattern]of challenges){const bad=clone(data);mutate(bad[slot]);const paths=writeFixture(name,bad);await nav('inputs');await upload(slot,paths[slot]);await rejectSetup(pattern);await nav('inputs');await upload(slot,writeFixture('canonical',data)[slot]);}
  const malformed=path.join(out,'inputs','unterminated.csv');fs.writeFileSync(malformed,'USUBJID,ARM,IMMFL,SAFEFL\nS1,A,Y,Y\nS2,A,Y,Y\nS3,A,Y,Y\nS4,A,Y,Y\nS5,A,Y,"Y\n');await fileInput('participants').setInputFiles(malformed);await settle();await expectState('invalid');assert.match(await frame.locator('#analysis_state').innerText(),/CSV|quot|record/i);await noStaleResults();await nav('inputs');await upload('participants',writeFixture('canonical',data).participants);
  await nav('study');await setValue('confidence',0);await rejectSetup(/confidence/i);await nav('study');await setValue('confidence',.95);
 });
 await scenario('Empty titer and diary files preserve unknown outcomes and denominators with native parity',async()=>{
  const empty={...clone(data),titers:[],diary:[]};await setup(cfg,writeFixture('empty',empty));await confirmAndRun();const result=await collectTables('empty',nativeExpected('empty',empty,cfg));
  assert.ok(result.tables['immunogenicity/01'].every(row=>row.n_evaluable==='0'&&row.geometric_mean===''));assert.ok(result.tables['reactogenicity/01'].every(row=>row.n_denominator==='0'&&row.percent===''));
 });
 await scenario('Configured BLQ and ALQ substitution matches the same scientific core in webR',async()=>{
  const censored=clone(data);censored.titers[0].AVAL=null;censored.titers[0].QUALIFIER='BLQ';censored.titers[1].AVAL=null;censored.titers[1].QUALIFIER='ALQ';const settings={...cfg,blq_policy:'half_lloq',alq_policy:'uloq',yes_value:'IN',no_value:'OUT',qualifier_exact:'QUANT',qualifier_blq:'BELOW',qualifier_alq:'ABOVE',qualifier_missing:'NOT_MEASURED'},source=clone(censored);
  for(const row of source.participants){row.IMMFL='IN';row.SAFEFL='IN';}for(const row of source.titers)row.QUALIFIER={EXACT:'QUANT',BLQ:'BELOW',ALQ:'ABOVE',MISSING:'NOT_MEASURED'}[row.QUALIFIER];
  await setup(settings,writeFixture('censored',source));await confirmAndRun();const result=await collectTables('censored',nativeExpected('censored',censored,settings));const x=cell(result.tables['immunogenicity/01'],{ARM:'A',VISIT:'Post'});near(x.geometric_mean,Math.cbrt(200*40*160),'Upper-limit substitution');assert.equal(x.n_substituted,'1');
 });
 await scenario('The app and generated report support both themes and desktop/mobile layouts',async()=>{
  for(const width of [1440,390])for(const theme of ['light','dark']){
   await page.setViewportSize({width,height:width===390?844:1000});const effective=await page.evaluate(()=>document.documentElement.dataset.theme||(matchMedia('(prefers-color-scheme: light)').matches?'light':'dark'));if(effective!==theme)await page.locator('.theme-toggle').first().click();await settle();await frame.waitForFunction(t=>document.documentElement.dataset.bsTheme===t,theme,{timeout:15000});
   for(const value of ['study','inputs','assay','diary','review','results']){await nav(value);assert.equal(await frame.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),true,'App overflow '+value+width+theme);if(['review','results'].includes(value)){const target=value==='review'?'#configuration_summary':'#result_summary';await frame.locator(target).scrollIntoViewIfNeeded();const element=await frame.frameElement();await element.evaluate(e=>{e.scrollIntoView({block:'start'});window.scrollBy(0,-60);});await shot('app-'+value+'-'+theme+'-'+width);}}
  }
  const html=baseline.inventory.filter(p=>p.endsWith('.html')).map(p=>path.join(baseline.directory,p));assert.equal(html.filter(p=>['index.html','analysis_report.html'].includes(path.basename(p))).length,7,'Summary and six output overviews');assert.ok(html.length>7,'Complete paginated table reports included');await checkDownloadedReportThemes({browser,files:html,directory:baseline.directory,output:out,report});
 });
 if(process.env.VACCINE_CAPACITY_QC==='1')await scenario('Actual webR capacity benchmark retains 140,000 expected diary assessments',async()=>{
  await page.setViewportSize({width:1440,height:1000});const participants=Array.from({length:1000},(_,i)=>({USUBJID:'P'+String(i+1).padStart(4,'0'),ARM:i<500?'A':'B',IMMFL:'N',SAFEFL:'Y'}));
  const symptoms=Array.from({length:10},(_,i)=>'Symptom '+(i+1)),doses=participants.flatMap(p=>['Dose 1','Dose 2'].map(DOSE=>({USUBJID:p.USUBJID,DOSE}))),diary=doses.flatMap(p=>Array.from({length:7},(_,DAY)=>symptoms.map(SYMPTOM=>({...p,DAY,SYMPTOM,GRADE:DAY%4}))).flat());
  const large={participants,titers:[],doses,diary},settings={...cfg,outputs:['reactogenicity','diary_profile'],symptoms:symptoms.join('\n'),day_end:6},files=writeFixture('capacity',large),started=Date.now();
  assert.equal(diary.length,140000);assert.ok(fs.statSync(files.diary).size<16*1024*1024,'Capacity input fits advertised per-file limit');await setup(settings,files);const configured=Date.now();await confirmAndRun(2,300000);const completed=Date.now();const result=await collectTables('capacity',nativeExpected('capacity',large,settings));
  assert.equal(result.tables['reactogenicity/01'].length,40);for(const row of result.tables['reactogenicity/01']){assert.equal(row.n_dosed,'500');assert.equal(row.n_complete,'500');assert.equal(row.n_missing_day_assessments,'0');assert.equal(row.percent,'100');}
  const daily=Object.values(result.tables).find(rows=>rows.length&&'DAY'in rows[0]&&'n_assessed'in rows[0]);assert.equal(daily.length,280);assert.ok(daily.every(r=>r.n_assessed==='500'&&r.n_missing==='0'));
  report.capacity={participants:1000,doses:2,symptoms:10,days:7,expected_assessments:140000,input_csv_bytes:fs.statSync(files.diary).size,upload_configuration_ms:configured-started,validate_compute_export_ms:completed-configured,native_parity_and_download_ms:Date.now()-completed,scope:'Measured in actual exported webR; no claim about untested larger data or device memory.'};await shot('capacity-results');
 });
 await scenario('Reset and real service-worker reload clear uploaded records, results and review approvals',async()=>{
  await frame.locator('#reset').click();await settle();await expectState('empty');await noStaleResults();await nav('review');for(const id of ['visits_confirmed','diary_confirmed','review_confirmed'])assert.equal(await frame.locator('#'+id).isChecked(),false);
  await page.reload({waitUntil:'domcontentloaded'});await ready();assert.equal(await state(),'empty');assert.equal(await unavailable('download_bundle'),true);assert.ok(!(await frame.locator('body').innerText()).includes(marker));
  for(const surface of [page,frame]){const storage=await surface.evaluate(()=>({local:{...localStorage},session:{...sessionStorage}}));assert.ok(!JSON.stringify(storage).includes(marker),'Participant records not persisted in browser key/value storage');}
 });
 await scenario('Participant records never reach the static host or external network; no uncaught script errors',async()=>{
  assert.equal(report.server_requests.filter(r=>!['GET','HEAD'].includes(r.method)||r.body_bytes>0||decodeURIComponent(r.path+r.query).includes(marker)).length,0,'Static host received no study uploads');
  const remote=report.network_requests.filter(r=>/^https?:/.test(r.url)&&new URL(r.url).origin!==new URL(base).origin);assert.equal(remote.filter(r=>!['GET','HEAD'].includes(r.method)||r.body_bytes>0||r.contains_synthetic_marker).length,0,'No participant records sent to external host');
  assert.deepEqual(remote,[],'Final exported app uses bundled dependencies without external package fetches');
  for(const request of report.network_requests.filter(r=>!['GET','HEAD'].includes(r.method)))assert.equal(request.from_service_worker,true,'Upload handled inside service worker: '+request.url);
  assert.equal(report.network_requests.filter(r=>r.contains_synthetic_marker&&r.method==='GET').length,0,'No participant IDs in request URLs');assert.deepEqual(report.errors,[]);assert.deepEqual(report.console_errors,[]);assert.equal(report.server_requests.filter(r=>r.status===404).length,0,'Exported site has no missing assets');
 });
 report.passed=true;
})().catch(async error=>{report.passed=false;report.failure=error.stack;console.error(error);if(page){await page.screenshot({path:path.join(out,'failure.png'),fullPage:false}).catch(()=>{});if(frame){report.failure_dom=await frame.locator('body').innerText().catch(()=>null);report.failure_ui=await frame.evaluate(()=>({viewport:innerWidth,scroll:document.documentElement.scrollWidth,confirmations:[...document.querySelectorAll('input[type=checkbox]')].map(e=>({id:e.id,value:e.value,checked:e.checked})),overflow:[...document.querySelectorAll('body *')].filter(e=>e.getBoundingClientRect().width&&e.getBoundingClientRect().right>innerWidth+1).slice(0,35).map(e=>({tag:e.tagName,id:e.id,class:e.className,width:e.getBoundingClientRect().width,right:e.getBoundingClientRect().right,text:(e.textContent||'').slice(0,120)}))})).catch(()=>null);}report.launch_status=await page.evaluate(()=>window.launchStatus||null).catch(()=>null);}process.exitCode=1;}).finally(async()=>{report.finished_at=new Date().toISOString();fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));if(browser)await browser.close();if(server)await new Promise(resolve=>{server.close(resolve);server.closeAllConnections();});console.log('Evidence: '+out);});
