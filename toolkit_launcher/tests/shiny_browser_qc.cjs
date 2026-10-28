/* Run each real R app through the local project's allowlisted launch plan. */
const { chromium }=require('playwright');
const cp=require('node:child_process'),fs=require('node:fs'),os=require('node:os'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../..'),tmp=fs.mkdtempSync(path.join(os.tmpdir(),'toolkit-shiny-'));
const out=process.env.QA_OUTPUT_DIR||path.join(tmp,'evidence');fs.mkdirSync(out,{recursive:true});
let browser,child;const report={apps:[],errors:[],external_email_sent:false};
(async()=>{
 const fixture=`import sys,json,tempfile,signal,threading\nsys.path.insert(0,sys.argv[1])\nfrom toolkit_launcher.runtime import Workspace\nfrom toolkit_launcher.server import create_server\nw=Workspace(sys.argv[2]);p=w.create_project('Synthetic browser check')\ns=create_server(w,'synthetic-test-token-'+('x'*40))\nsignal.signal(signal.SIGTERM,lambda *_:threading.Thread(target=s.shutdown,daemon=True).start())\nprint(json.dumps({'port':s.server_port,'project':p['id']}),flush=True)\ntry:s.serve_forever(poll_interval=.1)\nfinally:w.close();s.server_close()\n`;
 child=cp.spawn(process.env.TOOLKIT_PYTHON||'python3',['-u','-c',fixture,root,path.join(tmp,'private')],{stdio:['ignore','pipe','pipe']});
 const logs=[];child.stderr.on('data',d=>logs.push(d.toString()));
 const meta=await new Promise((resolve,reject)=>{let data='';const timer=setTimeout(()=>reject(Error('Portal timeout '+logs.join(''))),30000);child.stdout.on('data',d=>{data+=d;const line=data.split('\n').find(l=>l.startsWith('{'));if(line){clearTimeout(timer);resolve(JSON.parse(line));}});child.once('exit',c=>reject(Error('Portal exited '+c+logs.join(''))));});
 const base='http://127.0.0.1:'+meta.port,token='synthetic-test-token-'+'x'.repeat(40);
 browser=await chromium.launch({headless:true,...(process.env.CHROME_PATH?{executablePath:process.env.CHROME_PATH}:{})});const context=await browser.newContext();
 async function api(route,data){const r=await context.request.fetch(base+route,{method:data?'POST':'GET',headers:{'X-Toolkit-Token':token,'Origin':base},...(data?{data}:{}),timeout:60000});const v=await r.json();assert.equal(r.status(),200,JSON.stringify(v));return v;}
 for(const app of ['trialmon','lifecycle','uat','risk','hours']){
  let check=await api('/api/actions',{project_id:meta.project,action_id:`shiny.${app}.check`,options:{}});
  const until=async(id,test,seconds=60)=>{const end=Date.now()+seconds*1000;while(Date.now()<end){const state=await api('/api/jobs/'+id);if(test(state))return state;if(state.status==='failed')throw Error(app+': '+state.log);await new Promise(r=>setTimeout(r,200));}throw Error(app+' timed out');};
  check=await until(check.id,s=>s.status!=='running');assert.equal(check.status,'succeeded',check.log);
  let job=await api('/api/actions',{project_id:meta.project,action_id:`shiny.${app}.run`,options:{}});job=await until(job.id,s=>!!s.url);
  const page=await context.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));await page.goto(job.url,{waitUntil:'load'});
  await page.waitForFunction(()=>window.Shiny&&Shiny.shinyapp&&Shiny.shinyapp.$socket&&Shiny.shinyapp.$socket.readyState===1,{},{timeout:30000});
  await page.waitForTimeout(1500);assert.equal(await page.locator('.shiny-output-error:visible').count(),0);assert.deepEqual(errors,[]);
  await page.screenshot({path:path.join(out,app+'.png')});await page.close();await api('/api/jobs/'+job.id+'/stop',{});await until(job.id,s=>s.status!=='running');
  report.apps.push({id:app,passed:true});console.log('PASS local project app '+app);
 }
 await api('/api/stop',{});report.passed=true;
})().catch(e=>{report.passed=false;report.errors.push(e.stack);process.exitCode=1;console.error(e);}).finally(async()=>{if(browser)await browser.close();if(child&&child.exitCode===null){child.kill('SIGTERM');await new Promise(r=>{const t=setTimeout(()=>{child.kill('SIGKILL');r();},5000);child.once('exit',()=>{clearTimeout(t);r();});});}fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));fs.rmSync(tmp,{recursive:true,force:true});});
