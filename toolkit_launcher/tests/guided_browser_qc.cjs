/* Guided setup integration against the actual authenticated loopback server.
 * Synthetic CSVs only. Set TOOLKIT_QA_RUN_ANALYSIS=1 for actual R execution.
 * No model services, package downloads or email are invoked.
 * NODE_PATH=/path/to/node_modules CHROME_PATH=/path/to/chrome node toolkit_launcher/tests/guided_browser_qc.cjs
 */
const {chromium}=require('playwright');
const assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const cp=require('node:child_process'),crypto=require('node:crypto'),{once}=require('node:events'),{pathToFileURL}=require('node:url');
const root=path.resolve(__dirname,'../..'),temp=fs.mkdtempSync(path.join(os.tmpdir(),'toolkit-guided-fixture-'));
const workspace=path.join(temp,'private'),output=process.env.QA_OUTPUT_DIR?path.join(process.env.QA_OUTPUT_DIR,'guided-browser'):path.join(temp,'evidence');fs.mkdirSync(output,{recursive:true});
const report={started_at:new Date().toISOString(),scenarios:[],screenshots:[],errors:[],external_email_sent:false,model_calls:0,analysis_programs_executed:0};
let browser,child,page,base,token,project,schemas={},profiles={};
async function scenario(name,fn){await fn();report.scenarios.push({name,passed:true});console.log('PASS '+name);}
async function launch(){
  token=crypto.randomBytes(40).toString('hex');
  const code="import sys,os\nsys.path.insert(0,sys.argv[1])\nfrom toolkit_launcher.runtime import Workspace\nimport toolkit_launcher.server as web\nweb.open_native=lambda path:None\nw=Workspace(sys.argv[2])\ns=web.create_server(w,token=os.environ['TOOLKIT_QA_TOKEN'])\nprint('READY '+str(s.server_port),flush=True)\ntry:s.serve_forever()\nfinally:w.close();s.server_close()\n";
  child=cp.spawn(process.env.TOOLKIT_PYTHON||'python3',['-u','-c',code,root,workspace],{cwd:root,env:{...process.env,TOOLKIT_QA_TOKEN:token},stdio:['ignore','pipe','pipe']});
  let stdout='',stderr='';child.stdout.on('data',data=>stdout+=data);child.stderr.on('data',data=>stderr+=data);
  const port=await new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(Error('Server startup timeout: '+stderr)),30000);child.stdout.on('data',()=>{const match=stdout.match(/READY (\d+)/);if(match){clearTimeout(timer);resolve(match[1]);}});child.once('exit',code=>{clearTimeout(timer);reject(Error('Server exited '+code+': '+stderr));});});base='http://127.0.0.1:'+port;
}
async function api(route,body){const result=await fetch(base+route,{method:body===undefined?'GET':'POST',headers:{'X-Toolkit-Token':token,'Content-Type':'application/json'},...(body===undefined?{}:{body:JSON.stringify(body)})});const data=await result.json();assert.equal(result.status,200,JSON.stringify(data));return data;}
async function runFromCard(verb, expected='succeeded') {
  const label=verb==='check'?'Check analysis dependencies':'Run analysis and QC';
  const response=page.waitForResponse(response=>response.url().endsWith('/api/actions')&&response.request().method()==='POST');
  await page.locator('#guided-builds').getByRole('button',{name:label,exact:true}).first().click();
  const started=await (await response).json();assert.ok(started.id,JSON.stringify(started));
  await page.locator('#guided-dialog').waitFor({state:'hidden'});
  const deadline=Date.now()+60000;let job;
  while(Date.now()<deadline){job=(await api('/api/state')).jobs.find(job=>job.id===started.id);if(job&&['succeeded','failed','stopped'].includes(job.status))break;await new Promise(resolve=>setTimeout(resolve,250));}
  assert.equal(job?.status,expected,JSON.stringify(job));
  await page.locator('#refresh-status').click();
  await page.waitForFunction(expected=>document.querySelector('.job')?.dataset.job===expected.id&&document.querySelector('.job .badge')?.textContent===expected.status,{id:job.id,status:expected==='succeeded'?'Finished':'Failed'});
  return job;
}
async function downloadRun(job,name) {
  const outputFile=job.outputs.find(file=>file.path.endsWith('/results.zip'));assert.ok(outputFile,'Missing results ZIP');
  const pending=page.waitForEvent('download');await page.locator('.job').first().getByRole('button',{name:outputFile.label,exact:true}).click();
  const downloaded=await pending,archivePath=path.join(output,name+'.zip');await downloaded.saveAs(archivePath);
  const inspect="import sys,json,zipfile\nwith zipfile.ZipFile(sys.argv[1]) as z: print(json.dumps({'manifest':json.loads(z.read('output_manifest.json')),'qc':json.loads(z.read('qc.json'))}))";
  const evidence=JSON.parse(cp.execFileSync(process.env.TOOLKIT_PYTHON||'python3',['-c',inspect,archivePath],{encoding:'utf8'}));assert.equal(evidence.manifest.run_id,job.analysis.run_id);assert.equal(evidence.manifest.build_id,job.analysis.build_id);assert.equal(evidence.manifest.status,job.status);assert.equal(evidence.qc.passed,job.status==='succeeded');assert.equal(evidence.qc.approved,false);
  const reportFile=job.outputs.find(file=>file.path.endsWith('/analysis_report.html'));assert.ok(reportFile,'Missing report');
  const opened=page.waitForResponse(response=>response.url().endsWith('/api/files/open'));
  await page.locator('.job').first().getByRole('button',{name:'Open analysis report',exact:true}).click();assert.equal((await opened).status(),200);
  report.analysis_programs_executed++;
}
async function screenshot(name){await page.screenshot({path:path.join(output,name)});report.screenshots.push(name);}
async function open(moduleId){
  const snapshot=await api('/api/state'),module=snapshot.catalog.modules.find(module=>module.actions.some(action=>action.type==='guided'&&(action.module_id||action.id)===moduleId));assert.ok(module,'Missing guided catalog entry for '+moduleId);const action=module.actions.find(action=>action.type==='guided'&&(action.module_id||action.id)===moduleId);await page.locator(`[data-module="${module.id}"] button`).first().click();
  await page.locator('#tool-actions').getByRole('button',{name:action.label,exact:true}).click();await page.locator('#guided-dialog').waitFor({state:'visible'});
  const state=await api('/api/template-setup?'+new URLSearchParams({project_id:project,module_id:moduleId}));schemas[moduleId]=state.schema;return state;
}
async function close(){await page.locator('[data-close=guided-dialog]').click();await page.locator('#tool-dialog').waitFor({state:'visible'});await page.keyboard.press('Escape');}
async function step(moduleId,id){const steps=schemas[moduleId].steps;const index=steps.findIndex(step=>step.id===id);const target=index<0&&id==='review'?steps.length:index;assert.ok(target>=0,'Missing step '+id);await page.locator('#guided-nav button').nth(target).click();}
async function field(moduleId,id,value){const item=schemas[moduleId].steps.find(step=>(step.fields||[]).some(field=>field.id===id));assert.ok(item,'Missing field '+id);await step(moduleId,item.id);const definition=item.fields.find(field=>field.id===id),input=page.locator('#guided-field-'+id);if(definition.type==='select')await input.selectOption(String(value));else if(definition.type==='checkbox')await input.setChecked(value);else await input.fill(String(value));}
async function choices(moduleId,id,values){const owner=schemas[moduleId].steps.find(step=>(step.fields||[]).some(field=>field.id===id));assert.ok(owner,'Missing selections '+id);await step(moduleId,owner.id);const block=page.locator(`[data-guide-field="${id}"]`);await block.getByRole('button',{name:'Clear selection'}).click();for(const value of values)await block.locator('input[type=checkbox]').evaluateAll((inputs,value)=>{const input=inputs.find(input=>input.value===value);if(!input)throw Error('Unknown choice '+value);input.click();},value);}
async function upload(moduleId,slot,columns,rows,{rename=true}={}){
  await step(moduleId,'inputs');const card=page.locator(`.guided-input[data-slot="${slot}"]`);await card.waitFor();if(!await card.evaluate(el=>el.open))await card.locator('summary').first().click();
  const headers=columns.map(column=>rename?'source_'+column:column),csv=[headers.join(','),...rows.map(row=>row.map(value=>'"'+String(value).replaceAll('"','""')+'"').join(','))].join('\n')+'\n';
  await card.locator('input[type=file]').setInputFiles({name:slot+'-synthetic.csv',mimeType:'text/csv',buffer:Buffer.from(csv)});await card.getByRole('button',{name:/^(Add|Replace) CSV$/}).click();await page.waitForFunction(()=>document.getElementById('guided-status').textContent.startsWith('Added '));
  for(const [index,column] of columns.entries()){const select=page.locator('#guided-map-'+slot+'-'+column);if(await select.count()){if(rename)await select.selectOption(headers[index]);else assert.equal(await select.inputValue(),column);}}
  return csv;
}
async function validate(moduleId){await step(moduleId,'review');await page.locator('#guided-preview').click();await page.waitForFunction(()=>/Preview complete|Resolve the listed/.test(document.getElementById('guided-status').textContent));}
async function generate(moduleId){
  await validate(moduleId);assert.equal(await page.locator('#guided-report .report-errors').count(),0,await page.locator('#guided-report').innerText());assert.equal(await page.locator('#guided-generate').isDisabled(),true);await page.locator('#guided-review-check').check();assert.equal(await page.locator('#guided-generate').isEnabled(),true);await page.locator('#guided-generate').click();await page.waitForFunction(()=>document.getElementById('guided-status').textContent.startsWith('Configured package generated.'));
  const download=page.waitForEvent('download');await page.locator('#guided-builds').getByRole('button',{name:'Download complete package',exact:true}).first().click();const result=await download;assert.equal(fs.readFileSync(await result.path()).subarray(0,2).toString(),'PK');await result.saveAs(path.join(output,moduleId+'.zip'));
  const saved=await api('/api/template-setup?'+new URLSearchParams({project_id:project,module_id:moduleId}));assert.ok(saved.builds.length);assert.ok(saved.profile_path);profiles[moduleId]=JSON.parse(fs.readFileSync(path.join(workspace,'projects',project,'workspace',saved.profile_path),'utf8'));return saved;
}
(async()=>{
  await launch();browser=await chromium.launch({headless:true,...(process.env.CHROME_PATH?{executablePath:process.env.CHROME_PATH}:{})});const context=await browser.newContext({viewport:{width:1440,height:1000},acceptDownloads:true});page=await context.newPage();page.setDefaultTimeout(15000);page.on('pageerror',error=>report.errors.push(error.message));page.on('console',message=>{if(message.type()==='error'&&/Content Security Policy|Refused to/.test(message.text()))report.errors.push(message.text());});
  await page.goto(base+'/#launch-token='+token);await page.locator('#local-shell').waitFor({state:'visible'});await page.locator('#new-project').click();await page.locator('#project-name').fill('Synthetic guided study');await page.locator('#create-project').click();await page.locator('#project-dialog').waitFor({state:'hidden',timeout:30000});project=(await api('/api/state')).projects[0].id;
  for(const moduleId of ['r_tlf','sas_tlf'])await scenario(moduleId+' guided output selection, CSV mappings, validation and ZIP generation',async()=>{
    await open(moduleId);await field(moduleId,'study_id','STUDY-DEMO');await choices(moduleId,'outputs',['t_pk_param_summary']);await step(moduleId,'inputs');assert.equal(await page.locator('.guided-input').count(),1);
    const columns=['USUBJID','TRT01A','PKFL','PARAMCD','PARAM','AVAL','AVALU'];const row=['001','Drug A','Y','CMAX','Maximum concentration',12.5,'ng/mL'];if(moduleId==='sas_tlf'){columns.push('TRT01AN');row.push(1);}await upload(moduleId,'adpp',columns,[row]);
    await field(moduleId,'reviewed',true);await generate(moduleId);await screenshot(moduleId+'-generated.png');
    await field(moduleId,'study_id','STUDY-REVISED');await step(moduleId,'review');assert.equal(await page.locator('#guided-generate').isDisabled(),true);assert.equal(await page.locator('#guided-review-check').isChecked(),false);await close();
    await open(moduleId);assert.equal(await page.locator('#guided-field-study_id').inputValue(),'STUDY-DEMO');assert.equal(await page.locator('#guided-builds .guided-build').count(),1);await close();
  });
  await scenario('Study-specific baseline covariates appear as point-and-click mappings',async()=>{
    const id='r_tlf';await open(id);await choices(id,'outputs',['t_baseline_characteristics']);await field(id,'baseline_continuous','CUSTOM_SCORE');await field(id,'baseline_categorical','CUSTOM_GROUP');
    await upload(id,'adsl',['USUBJID','TRT01A','SAFFL','CUSTOM_SCORE','CUSTOM_GROUP'],[['001','Drug A','Y',3.25,'Category A']],{rename:true});
    assert.equal(await page.locator('#guided-map-adsl-CUSTOM_SCORE').count(),1);await validate(id);assert.equal(await page.locator('#guided-report .report-errors').count(),0,await page.locator('#guided-report').innerText());
    await field(id,'baseline_continuous','OTHER_SCORE');await step(id,'inputs');assert.equal(await page.locator('#guided-map-adsl-CUSTOM_SCORE').count(),0);assert.equal(await page.locator('#guided-map-adsl-OTHER_SCORE').count(),1);
    // Reopening returns the prior generated PK package, which remains immutable.
    await close();
  });
  await scenario('SAS monitoring validates mappings and blocks generation during input replacement',async()=>{
    const id='sas_monitor';await open(id);await field(id,'study_id','DEMO');await choices(id,'checks',['queries']);await upload(id,'queries',['OPEN_FL','QUERY_AGE_DAYS'],[['Y',35],['N',10]]);assert.equal(await page.locator('.guided-input').count(),1);await field(id,'query_days',28);await field(id,'review_confirmed',true);
    await step(id,'inputs');await page.locator('#guided-map-queries-OPEN_FL').selectOption('');await validate(id);assert.ok(await page.locator('#guided-report .report-errors').count());assert.equal(await page.locator('#guided-generate').isDisabled(),true);
    await step(id,'inputs');await page.locator('#guided-map-queries-OPEN_FL').selectOption('source_OPEN_FL');const saved=await generate(id);assert.equal(saved.values.query_days,28);
    await step(id,'inputs');const delayed=async route=>{await new Promise(resolve=>setTimeout(resolve,350));await route.continue();};await page.route('**/api/template-input',delayed);const card=page.locator('.guided-input[data-slot="queries"]');await card.locator('input[type=file]').setInputFiles({name:'queries-updated.csv',mimeType:'text/csv',buffer:Buffer.from('source_OPEN_FL,source_QUERY_AGE_DAYS\nY,45\nN,12\n')});
    const uploaded=page.waitForResponse(response=>response.url().endsWith('/api/template-input'));await card.getByRole('button',{name:'Replace CSV',exact:true}).click();assert.equal(await page.locator('#guided-preview').isDisabled(),true);assert.equal(await page.locator('#guided-generate').isDisabled(),true);assert.equal(await page.locator('#guided-next').isDisabled(),true);await uploaded;await page.waitForFunction(()=>document.getElementById('guided-status').textContent.startsWith('Added queries-updated.csv'));await page.unroute('**/api/template-input',delayed);await step(id,'review');assert.equal(await page.locator('#guided-generate').isDisabled(),true);assert.equal(await page.locator('#guided-preview').isEnabled(),true);assert.equal(await page.locator('#guided-review-check').isChecked(),false);await close();
  });
  await scenario('LOCALMIND maps existing findings and records labels without contacting a model',async()=>{
    const id='localmind';await open(id);await field(id,'study_id','DEMO');await field(id,'enable_model',true);await field(id,'model_name','example:latest');await field(id,'owner_labels','DATA MANAGEMENT\nPROGRAMMING\nSTATISTICS');await upload(id,'findings',['finding_id','rule','findtext'],[['F1','R1','Review missing visit date. <script>window.guidedInjected=1</script>']],{rename:false});assert.equal(await page.evaluate(()=>window.guidedInjected),undefined);assert.match(await page.locator('#guided-inputs').textContent(),/window.guidedInjected/);await field(id,'review_confirmed',true);await generate(id);await close();
  });
  await scenario('Aggregate interpretation shows factual preview and blocks unsupported numbers',async()=>{
    const id='interpretation';await open(id);await field(id,'study_id','DEMO');await field(id,'arm','Active');await field(id,'population_n',20);await field(id,'aggregate_confirmed',true);
    await upload(id,'ae_summary',['category','n','pct'],[['Any TEAE',10,50],['Related TEAE',4,20],['Severe TEAE',2,10],['SAE',1,5],['TEAE leading to discontinuation',1,5],['Death',0,0]],{rename:false});assert.equal(await page.locator('.guided-input').count(),1);await field(id,'review_confirmed',true);await validate(id);assert.match(await page.locator('#guided-report').innerText(),/Active|TEAE/);
    await field(id,'draft_text','There were 999 participants with adverse events.');await validate(id);assert.ok(await page.locator('#guided-report .report-errors').count());await field(id,'draft_text','');await generate(id);await screenshot('interpretation-preview.png');await close();
  });
  if(process.env.TOOLKIT_QA_RUN_ANALYSIS==='1') {
    await scenario('Generated analyses execute through real R and downloadable reports',async()=>{
      for(const id of (process.env.TOOLKIT_QA_RUN_TLF==='1'?['r_tlf','sas_tlf','sas_monitor','interpretation']:['sas_monitor','interpretation'])){
        await open(id);const installer=page.locator('#guided-builds .guided-build').first().locator('details');await installer.locator('summary').click();assert.equal(await installer.getByRole('button',{name:'Install analysis dependencies',exact:true}).isDisabled(),true);await installer.locator('input[type=checkbox]').check();assert.equal(await installer.getByRole('button',{name:'Install analysis dependencies',exact:true}).isEnabled(),true);await installer.locator('input[type=checkbox]').uncheck();
        await runFromCard('check');await open(id);const job=await runFromCard('run');assert.equal(job.analysis.module_id,id);await downloadRun(job,'analysis-'+id);await screenshot('analysis-'+id+'-success.png');
      }
    });
    await scenario('A pre-pinned synthetic facts mismatch fails visibly with downloadable diagnostics',async()=>{
      // Construct a signed negative fixture directly on disk, as a buggy generator
      // might. This bypasses generation on purpose, never analysis integrity checks.
      const directory=path.join(workspace,'projects',project,'workspace'),historyPath=path.join(directory,'toolkit_configuration/interpretation.builds.json');
      const history=JSON.parse(fs.readFileSync(historyPath,'utf8')),good=history[0],badId='setup-'+crypto.randomBytes(12).toString('hex');
      const oldPrefix='template_outputs/interpretation/'+good.build_id,newPrefix='template_outputs/interpretation/'+badId,bundle=path.join(directory,newPrefix);fs.cpSync(path.join(directory,oldPrefix),bundle,{recursive:true});
      const factsPath=path.join(bundle,'facts.json'),facts=JSON.parse(fs.readFileSync(factsPath,'utf8'));facts.__synthetic_mismatch__=123;fs.writeFileSync(factsPath,JSON.stringify(facts));
      const manifestPath=path.join(bundle,'analysis_bundle.json'),manifest=JSON.parse(fs.readFileSync(manifestPath,'utf8'));manifest.files['facts.json']=crypto.createHash('sha256').update(fs.readFileSync(factsPath)).digest('hex');fs.writeFileSync(manifestPath,JSON.stringify(manifest));
      const negative=JSON.parse(JSON.stringify(good).replaceAll(oldPrefix,newPrefix));negative.build_id=badId;negative.bundle_sha256=crypto.createHash('sha256').update(fs.readFileSync(manifestPath)).digest('hex');fs.writeFileSync(historyPath,JSON.stringify([negative,...history]));
      await open('interpretation');const failed=await runFromCard('run','failed');assert.equal(failed.analysis.build_id,badId);await downloadRun(failed,'analysis-failed');assert.ok(failed.outputs.some(file=>file.path.endsWith('/execution_error.json')));await screenshot('analysis-failure-diagnostics.png');
      fs.writeFileSync(historyPath,JSON.stringify(history));await open('interpretation');const retry=await runFromCard('run');assert.equal(retry.analysis.build_id,good.build_id);assert.notEqual(retry.analysis.run_id,failed.analysis.run_id);await downloadRun(retry,'analysis-recovered');
    });
  }
  await scenario('Saved setup profile downloads and imports without carrying source CSVs',async()=>{
    await open('r_tlf');await page.locator('#guided-dialog details').filter({has:page.locator('#guided-profile-file')}).locator('summary').click();const file=page.waitForEvent('download');await page.locator('#guided-profile-download').click();const download=await file;const profile=JSON.parse(fs.readFileSync(await download.path(),'utf8'));assert.equal(profile.module_id,'r_tlf');assert.equal(profile.values.study_id,'STUDY-DEMO');await close();
    await page.locator('#new-project').click();await page.locator('#project-name').fill('Independent synthetic import');await page.locator('#create-project').click();await page.locator('#project-dialog').waitFor({state:'hidden',timeout:30000});project=await page.locator('#project-select').inputValue();await open('r_tlf');
    const reuse=page.locator('#guided-dialog details').filter({has:page.locator('#guided-profile-file')});if(!await reuse.evaluate(el=>el.open))await reuse.locator('summary').click();await page.locator('#guided-profile-file').setInputFiles({name:'wrong-module.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify({...profile,module_id:'sas_tlf'}))});await page.locator('#guided-profile-import').click();await page.waitForFunction(()=>document.getElementById('guided-error').textContent.includes('module'));assert.equal(await page.locator('#guided-field-study_id').inputValue(),'');await page.locator('#guided-profile-file').setInputFiles({name:'setup.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(profile))});await page.locator('#guided-profile-import').click();await page.waitForFunction(()=>document.getElementById('guided-status').textContent.startsWith('Imported setup choices.'));assert.equal(await page.locator('#guided-field-study_id').inputValue(),'STUDY-DEMO');assert.equal(await page.locator('#guided-generate').isDisabled(),true);await validate('r_tlf');assert.ok(await page.locator('#guided-report .report-errors').count());const state=await api('/api/template-setup?'+new URLSearchParams({project_id:project,module_id:'r_tlf'}));assert.deepEqual(state.inputs,{});await close();
  });
  await scenario('Guided forms fit mobile and desktop in both light and dark modes',async()=>{
    await open('r_tlf');for(const theme of ['light','dark']){await page.evaluate(theme=>{localStorage.setItem('bp-theme',theme);document.documentElement.dataset.theme=theme;},theme);for(const width of [1440,390]){await page.setViewportSize({width,height:width===390?844:1000});await step('r_tlf','study');assert.equal(await page.evaluate(()=>document.getElementById('guided-dialog').scrollWidth<=document.getElementById('guided-dialog').clientWidth+1),true);await screenshot('guided-'+theme+'-'+width+'.png');}}await close();await page.setViewportSize({width:1440,height:1000});
  });
  await scenario('Closing tool details discards a late guided-setup response',async()=>{
    const delay=async route=>{await new Promise(resolve=>setTimeout(resolve,250));await route.continue();};await page.route('**/api/template-setup?*',delay);
    await page.locator('[data-module="sas_monitor"] button').first().click();const action=(await api('/api/state')).catalog.modules.find(module=>module.id==='sas_monitor').actions.find(action=>action.type==='guided');const received=page.waitForResponse(response=>response.url().includes('/api/template-setup?'));
    await page.locator('#tool-actions').getByRole('button',{name:action.label,exact:true}).click();await page.keyboard.press('Escape');await received;await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));assert.equal(await page.locator('#guided-dialog').isVisible(),false);await page.unroute('**/api/template-setup?*',delay);
  });
  await scenario('Downloaded HTML reports support light and dark themes on desktop and mobile',async()=>{
    const extract="import sys,json,pathlib,zipfile\np=pathlib.Path(sys.argv[1]);out=p/'reports';out.mkdir(exist_ok=True);files=[]\nfor z in sorted(p.glob('*.zip')):\n with zipfile.ZipFile(z) as package:\n  for i,name in enumerate(package.namelist()):\n   if name.endswith('.html'):\n    target=out/z.stem/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(package.read(name));files.append(str(target))\nprint(json.dumps(files))\n";
    const files=JSON.parse(cp.execFileSync(process.env.TOOLKIT_PYTHON||'python3',['-c',extract,output],{encoding:'utf8'}));assert.ok(files.length>=5);
    for(const file of files)for(const theme of ['light','dark'])for(const width of [1440,390]){
      // A fresh viewport avoids stale compositor strips after headless Chrome resize.
      const preview=await browser.newPage({viewport:{width,height:width===390?844:1000},colorScheme:theme});preview.on('pageerror',error=>report.errors.push(error.message));await preview.goto(pathToFileURL(file).href);
      assert.equal(await preview.locator('.theme-toggle').count(),1);await preview.evaluate(theme=>localStorage.setItem('bp-theme',theme),theme);await preview.reload();assert.equal(await preview.locator('html').getAttribute('data-theme'),theme);await preview.locator('.theme-toggle').click();assert.notEqual(await preview.locator('html').getAttribute('data-theme'),theme);await preview.locator('.theme-toggle').click();assert.equal(await preview.locator('html').getAttribute('data-theme'),theme);
      assert.equal(await preview.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),true,path.basename(file)+' horizontal overflow');const name='report-'+path.relative(path.join(output,'reports'),file).replace(/\.html$/,'').replaceAll(path.sep,'-')+'-'+theme+'-'+width+'.png';await preview.screenshot({path:path.join(output,name)});report.screenshots.push(name);await preview.close();
    }
    report.html_reports_checked=files.length;
  });
  await scenario('Guided pages produce no script errors or CSP violations',async()=>assert.deepEqual(report.errors,[]));
  await page.locator('#stop-launcher').click();await page.locator('#reconnect-panel').waitFor({state:'visible'});if(child.exitCode===null)await once(child,'exit');report.passed=true;console.log('Evidence: '+output);
})().catch(async error=>{if(page)try{await screenshot('failure.png');}catch{};report.passed=false;report.failure=String(error.stack).replaceAll(token||'__none__','[redacted]');console.error(report.failure);process.exitCode=1;}).finally(async()=>{if(browser)await browser.close();if(child&&child.exitCode===null)child.kill('SIGTERM');report.finished_at=new Date().toISOString();fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2));});
