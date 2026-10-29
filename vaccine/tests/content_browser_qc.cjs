/* Public guide and companion QA. No study data or external network is used.
 * NODE_PATH=/path/to/node_modules [CHROME_PATH=/path/to/chrome]
 * QA_OUTPUT_DIR=/path/to/evidence node vaccine/tests/content_browser_qc.cjs
 * Requires Playwright and Python 3. With no CHROME_PATH, uses installed Playwright Chromium.
 */
'use strict';
const {chromium}=require('playwright');
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os'),cp=require('node:child_process');
const root=path.resolve(__dirname,'../..');
const output=process.env.QA_OUTPUT_DIR?path.join(process.env.QA_OUTPUT_DIR,'vaccine-content'):fs.mkdtempSync(path.join(os.tmpdir(),'vaccine-content-qc-'));
fs.mkdirSync(output,{recursive:true});
const report={started_at:new Date().toISOString(),scenarios:[],screenshots:[],errors:[],external_requests:[]};
let browser,server,base;
async function scenario(name,fn){await fn();report.scenarios.push({name,passed:true});console.log('PASS '+name);}
async function start(){
  const code="from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler\nimport functools,sys\nclass Quiet(SimpleHTTPRequestHandler):\n def log_message(self,*args):pass\ns=ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Quiet,directory=sys.argv[1]))\nprint(s.server_port,flush=True)\ns.serve_forever()\n";
  server=cp.spawn(process.env.TOOLKIT_PYTHON||'python3',['-u','-c',code,root],{stdio:['ignore','pipe','pipe']});
  let stderr='';server.stderr.on('data',b=>stderr+=b);
  const port=await new Promise((resolve,reject)=>{let data='';const timer=setTimeout(()=>reject(Error('Static server timed out: '+stderr)),20000);server.stdout.on('data',b=>{data+=b;const found=data.match(/^(\d+)\s/m);if(found){clearTimeout(timer);resolve(found[1]);}});server.once('exit',status=>{clearTimeout(timer);reject(Error('Static server exited '+status+': '+stderr));});});
  base='http://127.0.0.1:'+port+'/vaccine/';
}
(async()=>{
  await start();browser=await chromium.launch({headless:true,...(process.env.CHROME_PATH?{executablePath:process.env.CHROME_PATH}:{})});
  const ctx=await browser.newContext(),page=await ctx.newPage();page.setDefaultTimeout(15000);
  page.on('pageerror',e=>report.errors.push(e.message));page.on('request',r=>{if(new URL(r.url()).origin!==new URL(base).origin)report.external_requests.push(r.url());});
  await scenario('Both public pages fit desktop/mobile and persist shared light/dark themes',async()=>{
    for(const filename of ['index.html','learning.html'])for(const width of [1440,390])for(const theme of ['light','dark']){
      await page.setViewportSize({width,height:width===1440?1000:844});await page.goto(base+filename);
      await page.evaluate(t=>localStorage.setItem('bp-theme',t),theme);await page.reload({waitUntil:'networkidle'});
      assert.equal(await page.locator('html').getAttribute('data-theme'),theme);
      assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,'Horizontal overflow: '+filename+width+theme);
      assert.equal(await page.locator('h1').count(),1);
      const shot=filename.replace('.html','')+'-'+theme+'-'+width+'.png';await page.screenshot({path:path.join(output,shot)});report.screenshots.push(shot);
      await page.locator('.theme-toggle').click();assert.notEqual(await page.locator('html').getAttribute('data-theme'),theme);
    }
    for(const filename of ['index.html','learning.html']){await page.setViewportSize({width:320,height:720});await page.goto(base+filename);assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,'Small-screen overflow: '+filename);}
  });
  await scenario('All local links and anchors exist; synthetic profile preserves review choices',async()=>{
    for(const filename of ['index.html','learning.html']){
      await page.goto(base+filename);const links=await page.locator('a[href]').evaluateAll(as=>as.map(a=>a.getAttribute('href')));
      for(const href of links){if(href.startsWith('#'))assert.equal(await page.locator(href).count(),1,filename+' anchor '+href);else if(!/^https?:/.test(href)){const response=await page.request.get(new URL(href,page.url()).href);assert.equal(response.status(),200,href);}}
    }
    const response=await page.request.get(base+'examples/example_profile.json');const profile=await response.json();assert.equal(profile.module_id,'vaccine');assert.equal(profile.schema,1);
    for(const key of ['visits_confirmed','diary_confirmed','review_confirmed'])assert.equal(profile.values[key],false,key);
    assert.deepEqual(Object.keys(profile).sort(),['module_id','schema','values']);
  });
  await scenario('Print controls invoke printing and include all expanded explanations in PDF',async()=>{
    for(const filename of ['index.html','learning.html']){
      await page.goto(base+filename);await page.evaluate(()=>{window.__printCount=0;window.print=()=>{window.__printCount++;};});
      for(const button of await page.locator('[data-print]').all())await button.click();
      assert.equal(await page.evaluate(()=>window.__printCount),await page.locator('[data-print]').count());
      await page.emulateMedia({media:'print'});await page.evaluate(()=>window.dispatchEvent(new Event('beforeprint')));
      assert.equal(await page.locator('details:not([open])').count(),0);
      const pdf=await page.pdf({path:path.join(output,filename.replace('.html','.pdf')),format:'A4',printBackground:true});assert.equal(pdf.subarray(0,4).toString(),'%PDF');
      await page.emulateMedia({media:'screen'});
    }
  });
  await scenario('Synthetic affinity explorer has correct direction and known-answer values',async()=>{
    await page.goto(base+'learning.html');
    for(const [value,expected] of [['1','90.9% occupied'],['10','50.0% occupied'],['100','9.1% occupied']]){await page.locator('#kd').selectOption(value);assert.equal(await page.locator('#occupancy').textContent(),expected);}
    await page.locator('#kd').focus();await page.keyboard.press('Home');await page.keyboard.press('Enter');assert.equal(await page.locator('#kd').evaluate(el=>document.activeElement===el),true);
  });
  await scenario('Self-check gives incomplete, correct and incorrect feedback without submission',async()=>{
    await page.locator('#quiz button').click();assert.match(await page.locator('#quiz-result').textContent(),/Choose an answer/);
    for(const [name,value] of [['q1','a'],['q2','b'],['q3','b']])await page.locator(`[name=${name}][value=${value}]`).check();
    await page.locator('#quiz button').click();assert.match(await page.locator('#quiz-result').textContent(),/3 of 3/);
    await page.locator('[name=q1][value=b]').check();await page.locator('#quiz button').click();assert.match(await page.locator('#quiz-result').textContent(),/2 of 3/);
    assert.equal(new URL(page.url()).pathname.endsWith('/vaccine/learning.html'),true);
  });
  await scenario('Public teaching pages make no external requests and have no script errors',async()=>{assert.deepEqual(report.errors,[]);assert.deepEqual(report.external_requests,[]);});
  report.passed=true;
})().catch(error=>{report.passed=false;report.failure=error.stack;console.error(error);process.exitCode=1;}).finally(async()=>{
  report.finished_at=new Date().toISOString();fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2));if(browser)await browser.close();if(server)server.kill();console.log('Evidence: '+output);
});
