/* Browser integration against the actual loopback server and native base-R jobs.
 * Only OS file/folder opening is captured; no apps, mail or model services are opened.
 * NODE_PATH=/path/to/node_modules CHROME_PATH=/path/to/chrome node toolkit_launcher/tests/real_browser_qc.cjs
 * QA_OUTPUT_DIR optionally selects the parent of the real-browser evidence directory.
 */
const {chromium}=require('playwright');
const assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const cp=require('node:child_process'),crypto=require('node:crypto'),{once}=require('node:events');
const root=path.resolve(__dirname,'../..');
const output=process.env.QA_OUTPUT_DIR?path.join(process.env.QA_OUTPUT_DIR,'real-browser'):fs.mkdtempSync(path.join(os.tmpdir(),'toolkit-real-browser-'));
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'toolkit-real-fixture-')),workspace=path.join(temp,'private'),opened=path.join(temp,'native-open.jsonl');
fs.mkdirSync(output,{recursive:true});
const report={started_at:new Date().toISOString(),scenarios:[],screenshots:[],errors:[],workspace,external_email_sent:false,model_calls:0,package_installations:0,limitations:['Native file/folder opening is captured to avoid opening applications during QA. Native file picker is covered by the contract fixture, not opened here.']};
let browser,child,base,token,projectId,projectRoot;
function capturedPaths(){return fs.readFileSync(opened,'utf8').trim().split('\n').filter(Boolean).map(line=>JSON.parse(line));}
function assertNativeOpened(expected){
  const identity=file=>{const stat=fs.statSync(file,{bigint:true});return `${stat.dev}:${stat.ino}`;};
  const wanted=identity(expected),actual=capturedPaths().map(file=>({path:file,identity:identity(file)}));
  assert.ok(actual.some(file=>file.identity===wanted),'Native-open file identity mismatch: '+JSON.stringify({expected,expected_identity:wanted,actual}));
}
async function scenario(name,fn){await fn();report.scenarios.push({name,passed:true});console.log('PASS '+name);}
async function launch(){
  token=crypto.randomBytes(40).toString('hex');
  const code=`import sys,json,os\nsys.path.insert(0,sys.argv[1])\nfrom toolkit_launcher.runtime import Workspace\nimport toolkit_launcher.server as web\ndef capture(path):\n with open(sys.argv[3],'a',encoding='utf-8') as out:out.write(json.dumps(str(path))+'\\n')\nweb.open_native=capture\nw=Workspace(sys.argv[2])\ns=web.create_server(w,token=os.environ['TOOLKIT_QA_TOKEN'])\nprint('READY '+str(s.server_port),flush=True)\ntry:s.serve_forever()\nfinally:w.close();s.server_close()\n`;
  child=cp.spawn(process.env.TOOLKIT_PYTHON||'python3',['-u','-c',code,root,workspace,opened],{cwd:root,env:{...process.env,TOOLKIT_QA_TOKEN:token},stdio:['ignore','pipe','pipe']});
  let stdout='',stderr='';child.stdout.on('data',data=>stdout+=data);child.stderr.on('data',data=>stderr+=data);
  const port=await new Promise((resolve,reject)=>{const timeout=setTimeout(()=>reject(Error('Server startup timeout: '+stderr)),30000);child.stdout.on('data',()=>{const match=stdout.match(/READY (\d+)/);if(match){clearTimeout(timeout);resolve(match[1]);}});child.once('exit',code=>{clearTimeout(timeout);reject(Error('Server exited '+code+': '+stderr));});});
  base='http://127.0.0.1:'+port;
}
async function state(){const response=await fetch(base+'/api/state',{headers:{'X-Toolkit-Token':token}});assert.equal(response.status,200);return response.json();}
async function finished(action,timeout=90000){const start=Date.now();while(Date.now()-start<timeout){const item=(await state()).jobs.find(job=>job.action_id===action);if(item&&item.status!=='running')return item;await new Promise(resolve=>setTimeout(resolve,200));}throw Error('Job timeout: '+action);}
async function screenshot(page,name){await page.evaluate(()=>scrollTo(0,0));await page.screenshot({path:path.join(output,name),fullPage:false});report.screenshots.push(name);}
async function waitExit(){if(child.exitCode!==null)return;await Promise.race([once(child,'exit'),new Promise((_,reject)=>setTimeout(()=>reject(Error('Server did not stop')),10000))]);}
(async()=>{
  await launch();browser=await chromium.launch({headless:true,...(process.env.CHROME_PATH?{executablePath:process.env.CHROME_PATH}:{})});
  const context=await browser.newContext({viewport:{width:1440,height:1000},acceptDownloads:true});
  const page=await context.newPage();page.on('pageerror',error=>report.errors.push(error.message));
  const consoleErrors=[];page.on('console',message=>{if(message.type()==='error')consoleErrors.push(message.text());});
  await page.goto(base+'/#launch-token='+token);await page.locator('#local-shell').waitFor({state:'visible'});
  await scenario('Actual server boots under CSP with all catalog cards and local runtime detection',async()=>{
    assert.equal(await page.locator('.tool-card').count(),22);assert.equal(new URL(page.url()).hash,'');const snapshot=await state();assert.equal(snapshot.runtime.r.available,true,'R is required for this integration check');report.r_path=snapshot.runtime.r.path;assert.equal(snapshot.projects.length,0);assert.equal(await page.locator('#project-empty').isVisible(),true);assert.equal(consoleErrors.some(message=>/Content Security Policy|Refused to/.test(message)),false);
  });
  await scenario('GUI creates a complete independent project and leaves source inputs untouched',async()=>{
    await page.locator('#new-project').click();await page.locator('#project-name').fill('Synthetic browser integration');await page.locator('#create-project').click();await page.locator('#project-dialog').waitFor({state:'hidden',timeout:30000});const snapshot=await state();assert.equal(snapshot.projects.length,1);projectId=snapshot.projects[0].id;projectRoot=path.join(workspace,'projects',projectId,'workspace');assert.ok(fs.existsSync(path.join(projectRoot,'sasr_monitoring_wiki/trialmon_shiny/app.R')));assert.ok(fs.existsSync(path.join(projectRoot,'toolkit_launcher/stub_profile.R')));assert.equal(await page.locator('#project-select').inputValue(),projectId);report.project_id=projectId;
  });
  await scenario('Input GUI replaces a private CSV, retains a revision backup and rejects wrong columns',async()=>{
    const relative='sasr_monitoring_wiki/trialmon_shiny/data/adsl.csv',original=fs.readFileSync(path.join(root,relative));
    await page.locator('[data-module="trialmon"] button').first().click();assert.ok((await page.locator('#tool-details a').first().getAttribute('href')).startsWith('https://patrickiben.github.io/biometrics-ai-portfolio/'));
    const row=page.locator('#tool-project .file-row').first();const replacement=Buffer.from(original.toString().replace(/\r?\n/,'\n'));
    await row.locator('input[type=file]').setInputFiles({name:'synthetic.csv',mimeType:'text/csv',buffer:replacement});await row.getByRole('button',{name:'Replace in project'}).click();await page.waitForFunction(()=>document.getElementById('tool-status').textContent.includes('Replaced'));
    assert.deepEqual(fs.readFileSync(path.join(projectRoot,relative)),replacement);assert.deepEqual(fs.readFileSync(path.join(root,relative)),original);assert.equal(fs.readdirSync(path.join(workspace,'projects',projectId,'input-backups')).length,1);
    await row.locator('input[type=file]').setInputFiles({name:'invalid.csv',mimeType:'text/csv',buffer:Buffer.from('wrong\nvalue\n')});await row.getByRole('button',{name:'Replace in project'}).click();await page.waitForFunction(()=>document.getElementById('tool-error').textContent.includes('column names'));assert.deepEqual(fs.readFileSync(path.join(projectRoot,relative)),replacement);
    await row.getByRole('button',{name:'Open / edit'}).click();await page.waitForFunction(()=>document.getElementById('tool-status').textContent.includes('Opened'));assertNativeOpened(path.join(projectRoot,relative));await page.keyboard.press('Escape');
  });
  await scenario('Configuration GUI saves numbers, reloads persisted values and rejects code-like text',async()=>{
    await page.locator('[data-module="sas_monitor"] button').first().click();await page.locator('#tool-actions').getByRole('button',{name:'Prepare monitoring configuration'}).click();await page.locator('#configure-form').waitFor({state:'visible'});
    await page.locator('#configure-fields-study_id').fill('SYNTHETIC-GUI');await page.locator('#configure-fields-alt_multiple').fill('3.5');await page.locator('#configure-fields-max_age').fill('48');await page.locator('#configure-form button[type=submit]').click();await page.waitForFunction(()=>document.getElementById('tool-status').textContent.includes('Configuration saved'));
    const configPath=path.join(projectRoot,'toolkit_configuration/sas_monitor.json'),saved=fs.readFileSync(configPath,'utf8');assert.equal(JSON.parse(saved).values.alt_multiple,3.5);assert.equal(JSON.parse(saved).values.max_age,48);
    await page.locator('#configure-fields-study_id').fill('BAD;system');await page.locator('#configure-form button[type=submit]').click();await page.waitForFunction(()=>document.getElementById('configure-error').textContent.length>0);assert.equal(fs.readFileSync(configPath,'utf8'),saved);await page.keyboard.press('Escape');
    await page.locator('[data-module="sas_monitor"] button').first().click();await page.locator('#tool-actions').getByRole('button',{name:'Prepare monitoring configuration'}).click();await page.locator('#configure-form').waitFor({state:'visible'});assert.equal(await page.locator('#configure-fields-study_id').inputValue(),'SYNTHETIC-GUI');assert.equal(await page.locator('#configure-fields-alt_multiple').inputValue(),'3.5');await page.keyboard.press('Escape');
  });
  await scenario('Runtime settings and native folder action use real server validation',async()=>{
    const detected=await state();await page.locator('#runtime-settings summary').click();await page.locator('#r-path').fill(detected.runtime.r.path);await page.locator('#settings-form button[type=submit]').click();await page.waitForFunction(()=>document.getElementById('message').textContent.includes('Runtime locations saved'));assert.equal((await state()).settings.r_path,detected.runtime.r.path);await page.locator('#runtime-settings summary').click();await page.locator('#open-folder').click();await page.waitForFunction(()=>document.getElementById('message').textContent.includes('Opened your private'));assertNativeOpened(projectRoot);
  });
  await scenario('Number validator runs actual R and exposes its real log',async()=>{
    await page.locator('[data-module="interpretation"] button').first().click();const module=(await state()).catalog.modules.find(module=>module.id==='interpretation');await page.locator('#tool-actions').getByRole('button',{name:module.actions.find(action=>action.id==='interpretation.check').label,exact:true}).click();await page.locator('#tool-dialog').waitFor({state:'hidden'});const job=await finished('interpretation.check');assert.equal(job.status,'succeeded',job.log);assert.match(job.log,/PASS|pass|OK|faithful/i);report.validator={status:job.status,log:job.log};await page.locator('#refresh-status').click();await page.waitForFunction(()=>document.querySelector('.job .badge')?.textContent==='Finished');
  });
  await scenario('Synthetic sandbox runs actual base R and downloads generated output',async()=>{
    await page.locator('[data-module="sandbox"] button').first().click();const module=(await state()).catalog.modules.find(module=>module.id==='sandbox');await page.locator('#tool-actions').getByRole('button',{name:module.actions.find(action=>action.id==='sandbox.run').label,exact:true}).click();await page.locator('#tool-dialog').waitFor({state:'hidden'});const job=await finished('sandbox.run');assert.equal(job.status,'succeeded',job.log);assert.ok(job.outputs.length>0);report.sandbox={status:job.status,outputs:job.outputs.map(output=>output.path),log:job.log};await page.locator('#refresh-status').click();await page.waitForFunction(()=>document.querySelectorAll('.job .outputs button').length>0);
    const download=page.waitForEvent('download');await page.locator(`.job[data-job="${job.id}"] .outputs button`).first().click();const result=await download;assert.ok(fs.statSync(await result.path()).size>0);await result.saveAs(path.join(output,'sample-'+result.suggestedFilename()));
  });
  await scenario('Actual private project exports as ZIP with configured inputs and outputs',async()=>{
    const download=page.waitForEvent('download',{timeout:30000});await page.locator('#export-project').click();const result=await download;const file=await result.path();assert.equal(fs.readFileSync(file).subarray(0,2).toString(),'PK');report.export_bytes=fs.statSync(file).size;assert.ok(report.export_bytes>10000);
  });
  await screenshot(page,'real-portal-desktop.png');await page.locator('[data-module="sas_monitor"] button').first().click();await page.locator('#tool-actions').getByRole('button',{name:'Prepare monitoring configuration'}).click();await page.locator('#configure-form').waitFor({state:'visible'});await screenshot(page,'real-configuration.png');await page.keyboard.press('Escape');
  await scenario('Closing and reopening the real service restores project and finished job history',async()=>{
    await page.locator('#stop-launcher').click();await page.locator('#reconnect-panel').waitFor({state:'visible'});await waitExit();await launch();await page.goto(base+'/#launch-token='+token);await page.locator('#local-shell').waitFor({state:'visible'});const snapshot=await state();assert.equal(snapshot.projects.length,1);assert.equal(snapshot.projects[0].id,projectId);assert.equal(snapshot.jobs.length,2);assert.equal(snapshot.jobs.every(job=>job.status==='succeeded'),true);assert.equal(await page.locator('.job').count(),2);await screenshot(page,'real-restored-history.png');
  });
  await scenario('No page errors or CSP violations in actual server integration',async()=>{assert.deepEqual(report.errors,[]);assert.equal(consoleErrors.some(message=>/Content Security Policy|Refused to/.test(message)),false);});
  await page.locator('#stop-launcher').click();await waitExit();report.passed=true;console.log('Evidence: '+output);
})().catch(error=>{report.passed=false;report.failure=String(error.stack).replaceAll(token||'__none__','[redacted]');console.error(report.failure);process.exitCode=1;}).finally(async()=>{if(browser)await browser.close();if(child&&child.exitCode===null)child.kill('SIGTERM');report.finished_at=new Date().toISOString();fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2));});
