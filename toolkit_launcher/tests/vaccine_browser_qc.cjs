/* Vaccine guided setup against the authenticated loopback server and real R.
 * Uses fictional CSVs only; no package downloads, models or email.
 * NODE_PATH=/path/to/node_modules CHROME_PATH=/path/to/chrome node toolkit_launcher/tests/vaccine_browser_qc.cjs
 */
'use strict';
const {chromium}=require('playwright');
const {checkDownloadedReportThemes}=require('./report_theme_qc.cjs');
const assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const cp=require('node:child_process'),crypto=require('node:crypto'),{once}=require('node:events');
const root=path.resolve(__dirname,'../..'),temp=fs.mkdtempSync(path.join(os.tmpdir(),'vaccine browser QC '));
const workspace=path.join(temp,'private'),output=process.env.QA_OUTPUT_DIR?path.join(process.env.QA_OUTPUT_DIR,'vaccine-browser'):path.join(temp,'evidence');
fs.mkdirSync(output,{recursive:true});
const settings=JSON.parse(fs.readFileSync(path.join(root,'vaccine/examples/example_settings.json'),'utf8'));
const report={started_at:new Date().toISOString(),scenarios:[],screenshots:[],errors:[],analysis_runs:[],external_email_sent:false,model_calls:0};
let browser,child,page,base,token,project,schema;
const pause=ms=>new Promise(resolve=>setTimeout(resolve,ms));
async function scenario(name,fn){await fn();report.scenarios.push({name,passed:true});console.log('PASS '+name);}
async function launch(){
  token=crypto.randomBytes(40).toString('hex');
  const code="import sys,os\nsys.path.insert(0,sys.argv[1])\nfrom toolkit_launcher.runtime import Workspace\nimport toolkit_launcher.server as web\nweb.open_native=lambda path:None\nw=Workspace(sys.argv[2])\ns=web.create_server(w,token=os.environ['TOOLKIT_QA_TOKEN'])\nprint('READY '+str(s.server_port),flush=True)\ntry:s.serve_forever()\nfinally:w.close();s.server_close()\n";
  child=cp.spawn(process.env.TOOLKIT_PYTHON||'python3',['-u','-c',code,root,workspace],{cwd:root,env:{...process.env,TOOLKIT_QA_TOKEN:token},stdio:['ignore','pipe','pipe']});
  let stdout='',stderr='';child.stdout.on('data',data=>stdout+=data);child.stderr.on('data',data=>stderr+=data);
  const port=await new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(Error('Server startup timeout: '+stderr)),30000);child.stdout.on('data',()=>{const found=stdout.match(/READY (\d+)/);if(found){clearTimeout(timer);resolve(found[1]);}});child.once('exit',code=>{clearTimeout(timer);reject(Error('Server exited '+code+': '+stderr));});});
  base='http://127.0.0.1:'+port;
}
async function api(route,body){const response=await fetch(base+route,{method:body===undefined?'GET':'POST',headers:{'X-Toolkit-Token':token,'Content-Type':'application/json'},...(body===undefined?{}:{body:JSON.stringify(body)})});const data=await response.json();assert.equal(response.status,200,JSON.stringify(data));return data;}
async function open(){
  await page.locator('[data-module="vaccine"] button').first().click();
  await page.locator('#tool-actions').getByRole('button',{name:'Set up vaccine analyses',exact:true}).click();
  await page.locator('#guided-dialog').waitFor({state:'visible'});
  const state=await api('/api/template-setup?'+new URLSearchParams({project_id:project,module_id:'vaccine'}));schema=state.schema;return state;
}
async function close(){await page.locator('[data-close=guided-dialog]').click();await page.locator('#tool-dialog').waitFor({state:'visible'});await page.keyboard.press('Escape');}
async function step(id){const index=schema.steps.findIndex(step=>step.id===id);const target=index<0&&id==='review'?schema.steps.length:index;assert.ok(target>=0,'Missing step '+id);await page.locator('#guided-nav button').nth(target).click();}
async function field(id,value){
  const owner=schema.steps.find(step=>(step.fields||[]).some(field=>field.id===id));assert.ok(owner,'Missing field '+id);await step(owner.id);
  const definition=owner.fields.find(field=>field.id===id),input=page.locator('#guided-field-'+id);
  if(['multiselect','template-select'].includes(definition.type)){
    const block=page.locator(`[data-guide-field="${id}"]`);await block.getByRole('button',{name:'Clear selection'}).click();
    for(const choice of value)await block.locator('input[type=checkbox]').evaluateAll((inputs,value)=>{const selected=inputs.find(input=>input.value===value);if(!selected)throw Error('Missing choice '+value);selected.click();},choice);
  }else if(definition.type==='select')await input.selectOption(String(value));else if(definition.type==='checkbox')await input.setChecked(value);else await input.fill(String(value));
}
async function inputCard(id){await step('inputs');const card=page.locator(`.guided-input[data-slot="${id}"]`);await card.waitFor();if(!await card.evaluate(node=>node.open))await card.locator('summary').first().click();return card;}
async function downloaded(button,filename){const pending=page.waitForEvent('download');await button.click();const download=await pending;assert.equal(download.suggestedFilename(),filename);const bytes=fs.readFileSync(await download.path());await download.saveAs(path.join(output,filename));return bytes;}
async function validate(){await step('review');await page.locator('#guided-preview').click();await page.waitForFunction(()=>/Preview complete|Resolve the listed/.test(document.getElementById('guided-status').textContent));}
async function screenshot(name){await page.screenshot({path:path.join(output,name)});report.screenshots.push(name);}
async function run(verb){
  const response=page.waitForResponse(result=>result.url().endsWith('/api/actions')&&result.request().method()==='POST');
  await page.locator('#guided-builds').getByRole('button',{name:verb==='check'?'Check analysis dependencies':'Run analysis and QC',exact:true}).first().click();
  const started=await(await response).json();assert.ok(started.id,JSON.stringify(started));await page.locator('#guided-dialog').waitFor({state:'hidden'});
  let job;const until=Date.now()+120000;
  while(Date.now()<until){job=(await api('/api/state')).jobs.find(item=>item.id===started.id);if(job&&['succeeded','failed','stopped'].includes(job.status))break;await pause(250);}
  assert.equal(job?.status,'succeeded',JSON.stringify(job));await page.locator('#refresh-status').click();
  await page.waitForFunction(id=>document.querySelector('.job')?.dataset.job===id&&document.querySelector('.job .badge')?.textContent==='Finished',job.id);
  return job;
}
async function inspectRun(job,number){
  const zipped=job.outputs.find(item=>item.path.endsWith('/results.zip'));assert.ok(zipped,'Missing results ZIP');
  const archive=path.join(output,'analysis-'+number+'.zip');const pending=page.waitForEvent('download');await page.locator('.job').first().getByRole('button',{name:zipped.label,exact:true}).click();await(await pending).saveAs(archive);
  const code="import sys,json,pathlib,zipfile\np=pathlib.Path(sys.argv[1]);out=p.parent/(p.stem+'-reports')\nwith zipfile.ZipFile(p) as z:\n names=z.namelist()\n assert all(not pathlib.PurePosixPath(n).is_absolute() and '..' not in pathlib.PurePosixPath(n).parts for n in names)\n z.extractall(out)\n print(json.dumps({'manifest':json.loads(z.read('output_manifest.json')),'qc':json.loads(z.read('qc.json')),'files':names,'html':[str(out/n) for n in names if n.endswith('.html')]}))\n";
  const evidence=JSON.parse(cp.execFileSync(process.env.TOOLKIT_PYTHON||'python3',['-c',code,archive],{encoding:'utf8'}));
  assert.equal(evidence.manifest.status,'succeeded');assert.equal(evidence.manifest.run_id,job.analysis.run_id);assert.equal(evidence.manifest.build_id,job.analysis.build_id);assert.equal(evidence.manifest.approved,false);assert.equal(evidence.qc.passed,true);assert.equal(evidence.qc.approved,false);
  assert.deepEqual(evidence.manifest.outputs.map(item=>item.id).sort(),[...settings.outputs].sort());
  for(const item of evidence.manifest.outputs){assert.equal(item.status,'completed');assert.ok(item.files.length);for(const file of item.files)assert.ok(evidence.files.includes(file),file);}
  for(const name of ['analysis_report.html','execution_status.csv','software_versions.csv'])assert.ok(evidence.files.includes(name));
  assert.ok(evidence.files.some(name=>name.endsWith('.csv')&&name.startsWith('outputs/')),'Missing numerical CSV exports');
  const opened=page.waitForResponse(result=>result.url().endsWith('/api/files/open'));await page.locator('.job').first().getByRole('button',{name:'Open analysis report',exact:true}).click();assert.equal((await opened).status(),200);
  report.analysis_runs.push({run_id:job.analysis.run_id,build_id:job.analysis.build_id,outputs:evidence.manifest.outputs.length,archive:path.basename(archive)});
  return evidence;
}
(async()=>{
  await launch();browser=await chromium.launch({headless:true,...(process.env.CHROME_PATH?{executablePath:process.env.CHROME_PATH}:{})});
  const context=await browser.newContext({viewport:{width:1440,height:1000},acceptDownloads:true});page=await context.newPage();page.setDefaultTimeout(20000);
  page.on('pageerror',error=>report.errors.push(error.message));page.on('console',message=>{if(message.type()==='error'&&/Content Security Policy|Refused to/.test(message.text()))report.errors.push(message.text());});
  await page.goto(base+'/#launch-token='+token);await page.locator('#local-shell').waitFor({state:'visible'});await page.locator('#new-project').click();await page.locator('#project-name').fill('Fictional vaccine browser QC');await page.locator('#create-project').click();await page.locator('#project-dialog').waitFor({state:'hidden',timeout:30000});project=(await api('/api/state')).projects[0].id;
  await scenario('Vaccine catalog opens guided setup with study choices left for the user',async()=>{
    const state=await open();assert.match(state.schema.title,/vaccine/i);assert.equal(state.values.study_id,'');
    for(const id of ['assay','antigen','unit','baseline_visit','followup_visits','dose_labels','symptoms'])assert.ok(!state.values[id]||Array.isArray(state.values[id])&&!state.values[id].length,'Scientific setting prefilled: '+id);
    await field('outputs',settings.outputs);
  });
  await scenario('All input templates and synthetic examples download; one-click examples use normal uploads',async()=>{
    for(const slot of schema.inputs){
      let card=await inputCard(slot.id);const templateName=slot.id+'_template.csv',sampleName=slot.id+'.csv';
      assert.deepEqual(await downloaded(card.getByRole('button',{name:'Download template',exact:true}),templateName),fs.readFileSync(path.join(root,'vaccine/examples',templateName)));
      assert.deepEqual(await downloaded(card.getByRole('button',{name:'Download synthetic example',exact:true}),sampleName),fs.readFileSync(path.join(root,'vaccine/examples',sampleName)));
      const response=page.waitForResponse(result=>result.url().endsWith('/api/template-input'));
      await card.getByRole('button',{name:'Use synthetic example',exact:true}).click();assert.equal((await response).status(),200);
      await page.waitForFunction(name=>document.getElementById('guided-status').textContent.startsWith('Added '+name),sampleName);
      card=await inputCard(slot.id);for(const raw of slot.columns){const id=typeof raw==='string'?raw:raw.id;assert.equal(await card.locator('[data-column="'+id+'"]').inputValue(),id);}
    }
    const after=await api('/api/template-setup?'+new URLSearchParams({project_id:project,module_id:'vaccine'}));assert.equal(Object.keys(after.inputs).length,4);
    await step(schema.steps.find(item=>(item.fields||[]).some(field=>field.id==='study_id')).id);assert.equal(await page.locator('#guided-field-study_id').inputValue(),'');
    await validate();assert.ok(await page.locator('#guided-report .report-errors').count());assert.equal(await page.locator('#guided-generate').isDisabled(),true);
  });
  await scenario('Explicit study settings and reviewed mappings produce an immutable runnable package',async()=>{
    for(const [id,value] of Object.entries(settings))await field(id,value);
    for(const fieldDef of schema.steps.flatMap(step=>step.fields||[]).filter(item=>item.type==='checkbox'&&item.id!=='outputs'))await field(fieldDef.id,true);
    await step('inputs');await page.locator('#guided-map-participants-USUBJID').selectOption('');await validate();assert.ok(await page.locator('#guided-report .report-errors').count());
    await step('inputs');await page.locator('#guided-map-participants-USUBJID').selectOption('USUBJID');await validate();assert.equal(await page.locator('#guided-report .report-errors').count(),0,await page.locator('#guided-report').innerText());
    assert.equal(await page.locator('#guided-generate').isDisabled(),true);await page.locator('#guided-review-check').check();await page.locator('#guided-generate').click();await page.waitForFunction(()=>document.getElementById('guided-status').textContent.startsWith('Configured package generated.'));
    const pending=page.waitForEvent('download');await page.locator('#guided-builds').getByRole('button',{name:'Download complete package',exact:true}).first().click();await(await pending).saveAs(path.join(output,'vaccine-setup.zip'));
    await screenshot('vaccine-generated.png');await close();
  });
  await scenario('Vaccine forms fit desktop and mobile in both themes',async()=>{
    await open();for(const theme of ['light','dark'])for(const width of [1440,390]){
      await page.evaluate(theme=>{localStorage.setItem('bp-theme',theme);document.documentElement.dataset.theme=theme;},theme);await page.setViewportSize({width,height:width===390?844:1000});
      for(const item of schema.steps){await step(item.id);assert.equal(await page.evaluate(()=>document.getElementById('guided-dialog').scrollWidth<=document.getElementById('guided-dialog').clientWidth+1),true,'Form overflow '+item.id);await screenshot('vaccine-form-'+item.id+'-'+theme+'-'+width+'.png');}
    }await close();await page.setViewportSize({width:1440,height:1000});
  });
  let first,second;
  await scenario('Dependency check and all six outputs run through the real point-and-click R workflow',async()=>{
    await open();await run('check');await open();first=await inspectRun(await run('run'),1);await screenshot('vaccine-run-success.png');
  });
  await scenario('Repeating the same generated package creates a distinct result revision',async()=>{
    await open();second=await inspectRun(await run('run'),2);assert.equal(first.manifest.build_id,second.manifest.build_id);assert.notEqual(first.manifest.run_id,second.manifest.run_id);
  });
  await scenario('Replacing an example clears prior preview approval and preserves uploaded-input history',async()=>{
    await open();await validate();await page.locator('#guided-review-check').check();const card=await inputCard('titers');await card.getByRole('button',{name:'Use synthetic example',exact:true}).click();await page.waitForFunction(()=>document.getElementById('guided-status').textContent.startsWith('Added titers.csv'));
    await step('review');assert.equal(await page.locator('#guided-generate').isDisabled(),true);assert.equal(await page.locator('#guided-review-check').isChecked(),false);
    const backups=fs.readdirSync(path.join(workspace,'projects',project,'input-backups'));assert.ok(backups.some(name=>name.startsWith('guided-vaccine-titers-')));await close();
  });
  await scenario('Deliberate example-profile import fills choices without data or review approval',async()=>{
    await page.locator('#new-project').click();await page.locator('#project-name').fill('Fictional vaccine profile import');await page.locator('#create-project').click();await page.locator('#project-dialog').waitFor({state:'hidden',timeout:30000});project=await page.locator('#project-select').inputValue();await open();
    const reuse=page.locator('#guided-dialog details').filter({has:page.locator('#guided-profile-file')});if(!await reuse.evaluate(el=>el.open))await reuse.locator('summary').click();
    await page.locator('#guided-profile-file').setInputFiles(path.join(root,'vaccine/examples/example_profile.json'));await page.locator('#guided-profile-import').click();await page.waitForFunction(()=>document.getElementById('guided-status').textContent.startsWith('Imported setup choices.'));
    await step('study');assert.equal(await page.locator('#guided-field-study_id').inputValue(),settings.study_id);
    for(const id of ['visits_confirmed','diary_confirmed','review_confirmed']){const owner=schema.steps.find(step=>(step.fields||[]).some(field=>field.id===id));await step(owner.id);assert.equal(await page.locator('#guided-field-'+id).isChecked(),false);}
    const state=await api('/api/template-setup?'+new URLSearchParams({project_id:project,module_id:'vaccine'}));assert.deepEqual(state.inputs,{});await validate();assert.ok(await page.locator('#guided-report .report-errors').count());assert.equal(await page.locator('#guided-generate').isDisabled(),true);await close();
  });
  await scenario('Exported analysis reports preserve theme controls and fit mobile and desktop',async()=>{
    await checkDownloadedReportThemes({browser,files:first.html,directory:path.join(output,'analysis-1-reports'),output,report});
  });
  await scenario('No script errors or content-security-policy violations occur',async()=>assert.deepEqual(report.errors,[]));
  await page.locator('#stop-launcher').click();await page.locator('#reconnect-panel').waitFor({state:'visible'});if(child.exitCode===null)await once(child,'exit');report.passed=true;console.log('Evidence: '+output);
})().catch(async error=>{if(page)try{await screenshot('failure.png');}catch{}report.passed=false;report.failure=String(error.stack).replaceAll(token||'__none__','[redacted]');console.error(report.failure);process.exitCode=1;}).finally(async()=>{if(browser)await browser.close();if(child&&child.exitCode===null)child.kill('SIGTERM');report.finished_at=new Date().toISOString();fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2));});
