/* Synthetic browser contract checks. No packages are installed and no external services are called.
 * NODE_PATH=/path/to/node_modules CHROME_PATH=/path/to/chrome node toolkit_launcher/tests/browser_qc.cjs
 * QA_OUTPUT_DIR optionally selects the parent of the browser-contract evidence directory.
 */
const {chromium}=require('playwright');
const assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const http=require('node:http'),cp=require('node:child_process'),crypto=require('node:crypto'),{once}=require('node:events');
const {pathToFileURL}=require('node:url');
const root=path.resolve(__dirname,'../..'),output=process.env.QA_OUTPUT_DIR?path.join(process.env.QA_OUTPUT_DIR,'browser-contract'):fs.mkdtempSync(path.join(os.tmpdir(),'toolkit-portal-browser-'));
fs.mkdirSync(output,{recursive:true});
const catalog=JSON.parse(fs.readFileSync(path.join(root,'toolkit_launcher/catalog.json'),'utf8'));
const metadata=JSON.parse(cp.execFileSync(process.env.TOOLKIT_PYTHON||'python3',['-c','import json;from toolkit_launcher.jobs import action_catalog,configuration_catalog;print(json.dumps(dict(actions=action_catalog(),configuration=configuration_catalog())))'],{cwd:root,encoding:'utf8'}));
const token=crypto.randomBytes(32).toString('hex');
const state={catalog,projects:[],projects_root:'/Synthetic/private/projects',runtime:{python:{available:true,version:'Python synthetic fixture'},r:{available:false,message:'Install R, then refresh'},quarto:{available:false,message:'Optional for rendered reports'}},jobs:[],settings:{r_path:'',quarto_path:''},...metadata};
const apiCalls=[],errors=[],report={started_at:new Date().toISOString(),scenarios:[],screenshots:[],limitations:['Chromium synthetic API contract fixture; native OS dialogs and R computations are tested separately.'],external_email_sent:false,package_installations:0};
let browser,server,base,deny=false,failUpload=false;
const config={sas_monitor:{study_id:'SYNTHETIC-01',max_age:36,alt_multiple:3.5}};
const template=fs.readFileSync(path.join(root,'toolkit_launcher/index.html'),'utf8');
function send(res,status,data,type='application/json'){res.writeHead(status,{'Content-Type':type,'Cache-Control':'no-store'});res.end(type==='application/json'?JSON.stringify(data):data);}
async function scenario(name,fn){await fn();report.scenarios.push({name,passed:true});console.log('PASS '+name);}
async function shot(page,name){await page.evaluate(()=>scrollTo(0,0));await page.screenshot({path:path.join(output,name),fullPage:page.viewportSize().width>600});report.screenshots.push(name);}
async function pageFor(context,url){const page=await context.newPage();page.on('pageerror',error=>errors.push(error.message));await page.goto(url);return page;}
function lastCall(route){return apiCalls.filter(call=>call.path===route).at(-1);}
function mutate(body,route,res){
  if(route==='/api/projects'){const project={id:'project-'+(state.projects.length+1),name:body.name,created_at:'2026-10-28'};state.projects.push(project);send(res,200,project);}
  else if(route==='/api/actions'){assert.ok(metadata.actions[body.action_id]||body.action_id==='tracker.setup');if(body.action_id.endsWith('.install'))assert.equal(body.options.allow_install,true);const job={id:'job-'+(state.jobs.length+1),action_id:body.action_id,module_id:metadata.actions[body.action_id]?.module_id,project_id:body.project_id,status:'running',log:'Synthetic log: <script>window.injected = true</script>',url:null,outputs:[]};state.jobs.push(job);send(res,200,job);}
  else if(/^\/api\/jobs\/[^/]+\/stop$/.test(route)){state.jobs.find(job=>job.id===route.split('/')[3]).status='stopped';send(res,200,{ok:true});}
  else if(route==='/api/settings'){state.settings=body;state.runtime.r={available:true,path:body.r_path,version:'Synthetic R'};send(res,200,{ok:true});}
  else if(route==='/api/pick-file')send(res,200,{path:body.kind==='r'?'/Synthetic/R/Rscript':'/Synthetic/Quarto/quarto'});
  else if(route==='/api/configure'){config[body.module_id]=body.values;send(res,200,{paths:['synthetic-config.json']});}
  else if(route==='/api/files'&&failUpload)send(res,400,{error:'Fixture rejects incompatible input columns.'});
  else if(route==='/api/stop'){deny=true;send(res,200,{ok:true});}
  else send(res,200,{ok:true});
}
(async()=>{
  server=http.createServer(async(req,res)=>{
    try{
      const url=new URL(req.url,'http://local');
      if(url.pathname.startsWith('/api/')){
        let raw='';for await(const chunk of req)raw+=chunk;const body=raw?JSON.parse(raw):undefined;
        apiCalls.push({path:url.pathname,query:Object.fromEntries(url.searchParams),method:req.method,body,token:req.headers['x-toolkit-token']});
        if(deny||req.headers['x-toolkit-token']!==token){send(res,401,{error:'The local launcher session has expired.'});return;}
        if(req.method==='POST'){mutate(body,url.pathname,res);return;}
        if(url.pathname==='/api/state'){send(res,200,state);return;}
        if(url.pathname==='/api/configure'){send(res,200,{values:config[url.searchParams.get('module_id')]||{}});return;}
        if(url.pathname==='/api/files'){send(res,200,'synthetic,file\n1,2\n','text/csv');return;}
        if(url.pathname.endsWith('/export')){send(res,200,'synthetic ZIP fixture','application/zip');return;}
        send(res,404,{error:'Unknown fixture route'});return;
      }
      if(url.pathname==='/'){send(res,200,template.replace('<html lang="en">','<html lang="en" data-managed="true">'),'text/html');return;}
      const map={'/portal.js':'toolkit_launcher/portal.js','/catalog.js':'toolkit_launcher/catalog.js','/assets/theme/tokens.css':'assets/theme/tokens.css'};
      if(map[url.pathname]){send(res,200,fs.readFileSync(path.join(root,map[url.pathname])),url.pathname.endsWith('.css')?'text/css':'text/javascript');return;}
      send(res,404,'Not found','text/plain');
    }catch(error){errors.push(error.stack);send(res,500,{error:error.message});}
  });server.listen(0,'127.0.0.1');await once(server,'listening');base='http://127.0.0.1:'+server.address().port;
  browser=await chromium.launch({headless:true,...(process.env.CHROME_PATH?{executablePath:process.env.CHROME_PATH}:{})});
  const context=await browser.newContext({viewport:{width:1440,height:1000},acceptDownloads:true});
  await scenario('Public file copy renders every module and never calls a server API',async()=>{
    const page=await context.newPage(),requests=[];page.on('pageerror',error=>errors.push(error.message));page.on('request',req=>requests.push(req.url()));
    await page.goto(pathToFileURL(path.join(root,'toolkit_launcher/index.html')).href+'#launch-token=discard-this-public-token');await page.locator('.tool-card').last().waitFor();
    assert.equal(await page.locator('.tool-card').count(),catalog.modules.length);assert.equal(await page.locator('#static-panel').isVisible(),true);assert.equal(await page.locator('#local-shell').isVisible(),false);assert.equal(new URL(page.url()).hash,'');
    assert.equal(requests.some(url=>url.includes('/api/')),false);assert.equal(await page.evaluate(()=>sessionStorage.getItem('toolkit-session-token')),null);
    assert.equal(await page.locator('a[href$="/undefined"]').count(),0);await page.locator('[data-module="trialmon"] button').first().click();await page.locator('#tool-dialog').waitFor({state:'visible'});assert.equal(await page.locator('#tool-project').isVisible(),false);await page.keyboard.press('Escape');await shot(page,'portal-public-desktop.png');await page.close();
  });
  const page=await pageFor(context,base+'/#launch-token='+token);await page.locator('#local-shell').waitFor({state:'visible'});
  await scenario('Private launch strips URL capability, preserves reload and reports missing R',async()=>{
    assert.equal(new URL(page.url()).hash,'');assert.equal(await page.evaluate(()=>sessionStorage.getItem('toolkit-session-token')),token);assert.equal(await page.evaluate(()=>localStorage.getItem('toolkit-session-token')),null);
    assert.match(await page.locator('#runtime-list').textContent(),/Install R/);assert.equal(await page.locator('#project-empty').isVisible(),true);assert.equal(apiCalls.every(call=>call.token===token),true);await page.reload();await page.locator('#local-shell').waitFor({state:'visible'});assert.equal(await page.locator('.tool-card').count(),22);
    await page.locator('#refresh-status').click();await page.waitForFunction(()=>document.getElementById('message').textContent.includes('status refreshed'));assert.equal(lastCall('/api/state').query.refresh,'1');
  });
  await scenario('Search and categories select the intended tool',async()=>{
    await page.locator('#search').fill('safety');assert.ok(await page.locator('.tool-card').count()>0);assert.ok(await page.locator('.tool-card').count()<catalog.modules.length);await page.locator('#search').fill('nothing-matches-this');assert.match(await page.locator('.catalog-empty').textContent(),/No tools match/);await page.locator('#search').fill('');await page.locator('#category').selectOption('Interactive apps');assert.equal(await page.locator('.tool-card').count(),5);await page.locator('#category').selectOption('all');
  });
  await scenario('Create private synthetic project and escape entered names',async()=>{
    await page.locator('#new-project').click();assert.equal(await page.locator('input[name="project-mode"]').count(),0);await page.locator('#project-name').fill('Synthetic <b>study</b>');await page.locator('#create-project').click();await page.locator('#project-dialog').waitFor({state:'hidden'});assert.equal(lastCall('/api/projects').body.name,'Synthetic <b>study</b>');assert.equal(await page.locator('#project-meta b').count(),0);assert.match(await page.locator('#project-meta').textContent(),/Synthetic <b>study<\/b>/);assert.equal(await page.locator('#project-select').inputValue(),'project-1');
  });
  await scenario('Install requires an explicit package-download checkbox',async()=>{
    await page.locator('[data-module="trialmon"] button').first().click();const count=apiCalls.filter(call=>call.path==='/api/actions').length;
    await page.locator('#tool-actions').getByRole('button',{name:'Install app packages'}).click();await page.locator('#run-form').waitFor({state:'visible'});await page.locator('#run-submit').click();assert.equal(apiCalls.filter(call=>call.path==='/api/actions').length,count);await page.locator('#run-fields-allow_install').check();await page.locator('#run-submit').click();await page.locator('#tool-dialog').waitFor({state:'hidden'});assert.deepEqual(lastCall('/api/actions').body,{project_id:'project-1',action_id:'shiny.trialmon.install',options:{allow_install:true}});assert.equal(await page.evaluate(()=>window.injected),undefined);assert.match(await page.locator('.log').first().textContent(),/<script>/);
  });
  await scenario('Run progress can be stopped and logs render as literal text',async()=>{
    assert.equal(await page.locator('.job .progress').count(),1);await page.locator('.job').first().getByRole('button',{name:'Stop',exact:true}).click();await page.waitForFunction(()=>document.querySelector('.job .badge').textContent==='Stopped');assert.equal(lastCall('/api/jobs/job-1/stop').method,'POST');assert.equal(await page.locator('.job .progress').count(),0);
  });
  await scenario('Numeric job options use actual JSON numbers and remain bounded',async()=>{
    await page.locator('[data-module="carryover"] button').first().click();await page.locator('#tool-actions').getByRole('button',{name:'Run carryover study'}).click();await page.locator('#run-fields-cores').fill('3');await page.locator('#run-submit').click();await page.locator('#tool-dialog').waitFor({state:'hidden'});assert.equal(lastCall('/api/actions').body.options.cores,3);
    const job=state.jobs.at(-1);job.status='succeeded';job.outputs=[{path:'outputs/synthetic.txt',label:'Synthetic output',url:'/api/files?project_id=project-1&path=outputs%2Fsynthetic.txt'}];await page.locator('#refresh-status').click();await page.waitForFunction(()=>document.querySelector('.job .badge').textContent==='Finished');assert.match(await page.locator('.job').first().textContent(),/Finished/);const download=page.waitForEvent('download');await page.locator('.job').first().getByRole('button',{name:'Synthetic output'}).click();assert.equal((await download).suggestedFilename(),'synthetic.txt');
  });
  await scenario('GUI input replacement sends exact allowlisted destination and shows rejection',async()=>{
    await page.locator('[data-module="trialmon"] button').first().click();const row=page.locator('#tool-project .file-row').first();const input=catalog.modules.find(module=>module.id==='trialmon').inputs[0];await row.getByRole('button',{name:'Open / edit'}).click();assert.equal(lastCall('/api/files/open').body.path,input.path);
    await row.locator('input[type=file]').setInputFiles({name:'synthetic.csv',mimeType:'text/csv',buffer:Buffer.from('A,B\n1,2\n')});await row.getByRole('button',{name:'Replace in project'}).click();await page.waitForFunction(()=>document.querySelector('#tool-project input[type=file]').value==='');assert.equal(lastCall('/api/files').body.path,input.path);assert.equal(Buffer.from(lastCall('/api/files').body.content_base64,'base64').toString(),'A,B\n1,2\n');assert.equal(await row.getByRole('button',{name:'Replace in project'}).isDisabled(),true);
    failUpload=true;await row.locator('input[type=file]').setInputFiles({name:'bad.csv',mimeType:'text/csv',buffer:Buffer.from('BAD\n')});await row.getByRole('button',{name:'Replace in project'}).click();await page.waitForFunction(()=>document.getElementById('tool-error').textContent.includes('incompatible'));assert.match(await page.locator('#tool-error').textContent(),/incompatible/);failUpload=false;await page.keyboard.press('Escape');
  });
  await scenario('Configuration forms reload existing values and save numeric thresholds',async()=>{
    await page.locator('[data-module="sas_monitor"] button').first().click();await page.locator('#tool-actions').getByRole('button',{name:'Prepare monitoring configuration'}).click();await page.locator('#configure-form').waitFor({state:'visible'});assert.equal(await page.locator('#configure-fields-study_id').inputValue(),'SYNTHETIC-01');assert.equal(await page.locator('#configure-fields-alt_multiple').inputValue(),'3.5');await page.locator('#configure-fields-max_age').fill('48');await page.locator('#configure-form button[type=submit]').click();await page.waitForFunction(()=>document.getElementById('tool-status').textContent.includes('Configuration saved'));assert.equal(lastCall('/api/configure').body.values.max_age,48);assert.equal(lastCall('/api/configure').body.module_id,'sas_monitor');await page.keyboard.press('Escape');
  });
  await scenario('Native runtime picker, folder button and authenticated project export work',async()=>{
    await page.locator('#runtime-settings summary').click();await page.locator('[data-pick=r]').click();await page.waitForFunction(()=>document.getElementById('r-path').value.includes('Synthetic'));assert.equal(await page.locator('#r-path').inputValue(),'/Synthetic/R/Rscript');await page.locator('#settings-form button[type=submit]').click();await page.waitForFunction(()=>document.getElementById('message').textContent.includes('Runtime locations saved'));assert.equal(lastCall('/api/settings').body.r_path,'/Synthetic/R/Rscript');await page.locator('#runtime-settings summary').click();await page.locator('#open-folder').click();assert.equal(lastCall('/api/projects/project-1/open').method,'POST');const download=page.waitForEvent('download');await page.locator('#export-project').click();assert.match((await download).suggestedFilename(),/\.zip$/);
  });
  await scenario('Light and dark themes persist; desktop and mobile fit without horizontal scrolling',async()=>{
    for(const theme of ['light','dark']){await page.evaluate(theme=>{localStorage.setItem('bp-theme',theme);document.documentElement.dataset.theme=theme;},theme);await page.reload();await page.locator('#local-shell').waitFor({state:'visible'});assert.equal(await page.locator('html').getAttribute('data-theme'),theme);await shot(page,'portal-'+theme+'-desktop.png');}
    const before=await page.locator('html').getAttribute('data-theme');await page.locator('.theme-toggle').click();assert.notEqual(await page.locator('html').getAttribute('data-theme'),before);await page.setViewportSize({width:390,height:844});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);await shot(page,'portal-light-mobile.png');await page.locator('[data-module="sas_monitor"] button').first().click();assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);await shot(page,'portal-mobile-dialog.png');await page.keyboard.press('Escape');await page.setViewportSize({width:1440,height:1000});
  });
  await scenario('Expired sessions hide private controls and stop authenticated polling',async()=>{
    deny=true;await page.locator('#refresh-status').click();await page.locator('#reconnect-panel').waitFor({state:'visible'});assert.equal(await page.locator('#local-shell').isVisible(),false);assert.equal(await page.evaluate(()=>sessionStorage.getItem('toolkit-session-token')),null);const count=apiCalls.length;await page.waitForTimeout(2800);assert.equal(apiCalls.length,count);
  });
  await scenario('No script errors, unescaped injection or credential leakage',async()=>{assert.deepEqual(errors,[]);assert.equal(apiCalls.every(call=>call.token===token),true);assert.equal(await page.evaluate(()=>window.injected),undefined);});
  report.passed=true;report.api_requests=apiCalls.length;console.log('Evidence: '+output);
})().catch(error=>{report.passed=false;report.failure=error.stack;console.error(error);process.exitCode=1;}).finally(async()=>{report.finished_at=new Date().toISOString();report.errors=errors;fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2));if(browser)await browser.close();if(server)server.close();});
