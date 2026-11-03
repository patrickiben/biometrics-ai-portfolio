// Real Pyodide + webR execution. No host R is available to the page.
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const fs=require('node:fs/promises'),path=require('node:path'),assert=require('node:assert/strict');
const base=process.argv[2]||'http://127.0.0.1:8874',output=process.argv[3]||'/tmp/toolkit-validation-browser-qc',mode=process.argv[4]||'harness';
(async()=>{
 await fs.mkdir(output,{recursive:true});const browser=await chromium.launch({headless:true,...(process.env.CHROME_PATH?{executablePath:process.env.CHROME_PATH}:{channel:'chrome'})});
 const page=await browser.newPage({viewport:{width:1440,height:1000}});const errors=[],requests=[];const report={passed:false,mode,started:new Date().toISOString()};
 page.on('pageerror',e=>errors.push(e.message));page.on('request',r=>requests.push(r.url()));page.on('console',m=>{if(m.text().startsWith('QC '))console.log(m.text());});
 async function save(name,result){await fs.writeFile(path.join(output,name+'.json'),JSON.stringify({...result,files:result.files?.map(f=>({path:f.path,base64_bytes:f.base64.length}))},null,2));for(const file of result.files||[]){const p=path.join(output,name,file.path);await fs.mkdir(path.dirname(p),{recursive:true});await fs.writeFile(p,Buffer.from(file.base64,'base64'));}}
 try{
  await page.goto(base+'/browser_modules/workbench/',{waitUntil:'networkidle'});
  await page.evaluate(async()=>{const {BrowserRuntime}=await import('./runtime.mjs');window.QC=new BrowserRuntime(message=>console.log('QC progress',message));window.QC_CALLS=[];const original=QC.runRCommand.bind(QC);QC.runRCommand=async request=>{const started=performance.now(),id=QC_CALLS.length+1;console.log('QC R start',id,request.argv.slice(1,3).join(' ').slice(0,150));const result=await original(request);QC_CALLS.push({id,argv:request.argv,cwd:request.cwd,seconds:(performance.now()-started)/1000,returncode:result.returncode,stdout:result.stdout,stderr:result.stderr});console.log('QC R done',id,result.returncode);return result;};});
  const meta=await page.evaluate(()=>QC.python('validation-init',{}));assert.equal(meta.registry.length,18);assert.equal(meta.supports_uploads,false);report.metadata=meta;console.log('QC reviewed sources loaded',meta.source_files);
  const initial=await page.evaluate(()=>QC.python('validation-harness',{}));await save('initial-harness',initial);assert.equal(initial.ok,true,initial.error);report.gates=initial.ledger.gates;console.log('QC gates',report.gates.map(x=>x.gate.split(' ')[0]+':'+x.status).join(' '));
  const gates=Object.fromEntries(report.gates.map(g=>[g.gate.split(' ')[0],g]));assert.equal(gates.G5.status,'manual');assert.equal(gates.G7.status,'not signed');assert.equal(gates.G10.status,'stale');
  for(const g of ['G1','G2','G3','G4','G6','G8','G9'])assert.equal(gates[g].status,'green',g+': '+gates[g].evidence);
  if(mode==='full'||mode.startsWith('D')){
   const teeth=await page.evaluate(only=>QC.python('validation-teeth',{only}),mode==='full'?'':mode);await save('teeth',teeth);assert.equal(teeth.ok,true,teeth.error);report.teeth=teeth.summary;
   if(mode==='full'){
    assert.equal(teeth.summary.n_run,18);assert.equal(teeth.summary.partial,false);assert.deepEqual(teeth.summary.counts,{CAUGHT:15,SURVIVED:0,EQUIVALENT:1,'NOT APPLICABLE':2});
    const final=await page.evaluate(()=>QC.python('validation-harness',{}));await save('final-harness',final);assert.equal(final.ledger.gates.at(-1).status,'green');report.final_gates=final.ledger.gates;
   }else assert.equal(teeth.summary.partial,true);
  }
  assert.deepEqual(errors,[]);assert.ok(requests.every(url=>new URL(url).origin===new URL(base).origin),'All runtime/data requests must use the served toolkit origin.');report.passed=true;
 }catch(error){report.error=String(error.stack||error);throw error;}
 finally{report.calls=await page.evaluate(()=>window.QC_CALLS||[]).catch(()=>[]);report.errors=errors;report.requests=requests;report.finished=new Date().toISOString();await fs.writeFile(path.join(output,'report.json'),JSON.stringify(report,null,2));await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
