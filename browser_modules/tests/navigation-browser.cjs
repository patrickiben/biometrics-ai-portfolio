/* Catalog, guide, launch-shell and theme QC. Module execution has separate tests.
 * node browser_modules/tests/navigation-browser.cjs SITE [EVIDENCE]
 * TOOLKIT_LIVE_BASE=https://host/biometrics-ai-portfolio enables the same read-only live checks.
 * Integrated eCRF uploads and downloads have separate execution tests.
 */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const site = path.resolve(process.argv[2] || '_site');
const evidence = path.resolve(process.argv[3] || process.env.QA_OUTPUT_DIR || 'navigation-qc');
const prefix = '/biometrics-ai-portfolio';
const mime = {'.html':'text/html','.js':'text/javascript','.mjs':'text/javascript','.css':'text/css','.json':'application/json','.svg':'image/svg+xml','.png':'image/png','.webp':'image/webp','.wasm':'application/wasm','.woff2':'font/woff2'};
const guides = [
  ['sasr_monitoring_wiki/index.html','apps/trialmon/'],
  ['lifecycle_dashboard/quarto/lifecycle-guide.html','apps/lifecycle_dashboard/'],
  ['uat_irt/quarto/uat-guide.html','apps/uat_irt/'],
  ['risk_monitor/quarto/risk-guide.html','apps/risk/'],
  ['budget_reconciliation/quarto/hours-guide.html','apps/hours/'],
  ['study/index.html','apps/methods/?module=study'],
  ['sim_lifecycle/index.html','apps/methods/?module=sandbox'],
  ['sim_lifecycle/carryover_oc/index.html','apps/methods/?module=carryover'],
  ['cqtc_hysteresis/index.html','apps/methods/?module=cqtc'],
  ['vaccine/index.html','apps/vaccine/'],
  ['r_tlf_pseudocode/index.html','browser_modules/workbench/?module=r_tlf'],
  ['sas_tlf_pseudocode/index.html','browser_modules/workbench/?module=sas_tlf'],
  ['tlf_interpret/index.html','browser_modules/workbench/?module=interpretation'],
  ['sas_r_automation/SAS_R_Trial_Monitoring_Automation.html','browser_modules/workbench/?module=sas_monitor'],
  ['validation_harness/index.html','browser_modules/workbench/?module=harness'],
  ['validation_harness/index.html#teeth','browser_modules/workbench/?module=teeth']
];
fs.mkdirSync(evidence,{recursive:true});
const report={scope:'Navigation, rendered catalog links, local documents, launch shells and light/dark/mobile presentation. Full R execution and exports are checked by the separate module tests.',modules:[],documents:[],pages:[],guides:[],external:[],errors:[]};
let server,browser,base;
function canonical(value){const u=new URL(value,base+'/');return u.origin+u.pathname+u.search;}
async function inspectLocal(relative,screen=false){
  const page=await browser.newPage({viewport:{width:1360,height:900}}),errors=[];
  page.on('pageerror',e=>errors.push(String(e)));
  try{
    const response=await page.goto(base+'/'+relative,{waitUntil:'domcontentloaded',timeout:60000});
    assert(response?.ok(),`${relative}: HTTP ${response?.status()}`);
    const title=await page.title();assert(title.trim(),relative+': page title');
    const toggle=page.locator('.theme-toggle:visible').first();
    await toggle.waitFor({state:'visible',timeout:15000});
    await toggle.click();
    const middle=await page.evaluate(()=>({theme:document.documentElement.dataset.theme||'',color:getComputedStyle(document.body).color,bg:getComputedStyle(document.body).backgroundColor}));
    assert(['light','dark'].includes(middle.theme),relative+': explicit theme toggle');
    await toggle.click();
    const after=await page.evaluate(()=>({theme:document.documentElement.dataset.theme||'',color:getComputedStyle(document.body).color,bg:getComputedStyle(document.body).backgroundColor}));
    assert.notEqual(middle.theme,after.theme,relative+': both themes reachable');
    assert(middle.color!==after.color||middle.bg!==after.bg,relative+': colors respond to theme');
    await page.setViewportSize({width:390,height:844});
    await page.waitForTimeout(80);
    const mobile=await page.evaluate(()=>({width:innerWidth,scroll:document.documentElement.scrollWidth}));
    assert(mobile.scroll<=mobile.width+2,`${relative}: horizontal overflow ${mobile.scroll}/${mobile.width}`);
    if(screen)await page.screenshot({path:path.join(evidence,relative.replace(/[^A-Za-z0-9_-]/g,'_')+'-phone.png'),fullPage:false});
    assert.deepEqual(errors,[],relative+': script errors');
    const links=await page.locator('a[href]').evaluateAll(nodes=>nodes.map(n=>({href:n.href,text:(n.textContent||'').trim(),visible:!!n.getClientRects().length&&getComputedStyle(n).visibility!=='hidden'})));
    report.pages.push({path:relative,title,themes:[middle.theme,after.theme],mobile,scope:relative.startsWith('apps/')?'launch shell':'browser page'});
    return links;
  }finally{await page.close();}
}
(async()=>{
  if(process.env.TOOLKIT_LIVE_BASE)base=process.env.TOOLKIT_LIVE_BASE.replace(/\/$/,'');
  else{
    server=http.createServer((req,res)=>{
      try{
        const u=new URL(req.url,'http://localhost');if(!u.pathname.startsWith(prefix+'/'))throw Error();
        let file=path.resolve(site,'.'+decodeURIComponent(u.pathname.slice(prefix.length)));if(!file.startsWith(site+path.sep))throw Error();
        if(fs.statSync(file).isDirectory())file=path.join(file,'index.html');
        res.setHeader('Content-Type',mime[path.extname(file)]||'application/octet-stream');fs.createReadStream(file).pipe(res);
      }catch{res.writeHead(404).end();}
    });
    await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));base=`http://127.0.0.1:${server.address().port}${prefix}`;
  }
  report.base=base;
  browser=await chromium.launch(process.env.CHROME_PATH?{executablePath:process.env.CHROME_PATH,headless:true}:{channel:'chrome',headless:true});
  const catalogPage=await browser.newPage();
  await catalogPage.goto(base+'/toolkit_launcher/index.html');
  await catalogPage.locator('.tool-card').last().waitFor();
  const catalog=await catalogPage.evaluate(async()=>{const r=await fetch('catalog.json');if(!r.ok)throw Error('Catalog request failed');return r.json();});
  assert.equal(catalog.modules.length,23,'registered modules');
  assert.equal(await catalogPage.locator('.tool-card').count(),23,'all catalog cards rendered');
  const routes=new Set(),documents=new Set(['index.html','GET_STARTED.html','START_HERE.html','TOOLKIT_SETUP.html','toolkit_launcher/index.html']);
  for(const m of catalog.modules){
    const target=m.browser_path?canonical(m.browser_path):canonical(m.demo_url);
    const card=catalogPage.locator(`.tool-card[data-module="${m.id}"]`);assert.equal(await card.count(),1,m.id+': catalog card');
    const href=await card.locator('a.primary').getAttribute('href');assert.equal(canonical(href),target,m.id+': primary browser route');
    assert((await card.innerText()).includes(m.browser_label),m.id+': scope label');
    if(m.browser_path)routes.add(m.browser_path);
    for(const doc of m.docs||[])if(!/^https?:/.test(doc.path)&&/\.html(?:[?#]|$)/.test(doc.path))documents.add(doc.path);
    report.modules.push({id:m.id,title:m.title,url:target,scope:m.browser_label});
  }
  for(const relative of new Set(catalog.modules.flatMap(m=>(m.docs||[]).map(x=>x.path)).filter(x=>!/^https?:/.test(x)))){
    const response=await catalogPage.request.get(base+'/'+relative,{timeout:60000});
    assert(response.ok(),relative+': local documentation HTTP '+response.status());
    report.documents.push({path:relative,status:response.status()});await response.dispose();
  }
  await catalogPage.close();
  const pages=new Map();
  for(const relative of new Set([...routes,...documents,...guides.map(x=>x[0])])){
    console.log('Navigation QC:',relative);
    pages.set(relative,await inspectLocal(relative,['TOOLKIT_SETUP.html','toolkit_launcher/index.html','browser_modules/register/','browser_modules/workbench/?module=r_tlf'].includes(relative)));
  }
  const setupLinks=pages.get('TOOLKIT_SETUP.html');
  for(const m of report.modules)assert(setupLinks.some(x=>canonical(x.href)===m.url),'Setup guide route: '+m.id);
  for(const [from,to] of guides){
    const link=pages.get(from).find(x=>x.visible&&canonical(x.href)===canonical(to));
    if(!link)report.errors.push(`${from}: visible browser-workspace guide link missing for ${to}`);
    report.guides.push({from,to,text:link?.text,found:!!link});
  }
  for(const m of catalog.modules.filter(x=>!x.browser_path)){
    const page=await browser.newPage();
    try{
      const response=await page.goto(m.demo_url,{waitUntil:'domcontentloaded',timeout:60000});
      assert(response?.ok(),m.id+': external public route');
      const title=await page.title(),text=await page.locator('body').innerText();assert(title.trim(),m.id+': external title');
      const controls=await page.locator('input[type="file"]').evaluateAll(nodes=>nodes.map(n=>({id:n.id,disabled:n.disabled})));
      report.external.push({id:m.id,url:page.url(),title,fileInputs:controls,scopeMentions:text.split('\n').filter(s=>/upload|synthetic|placeholder|MedDRA|validat|demo/i.test(s)).slice(0,18),readOnly:true});
      if(m.id==='ecrf')assert(/upload[^\n]{0,100}disabled|disabled[^\n]{0,100}upload|every data input is locked/i.test(text),'External demo still identifies locked inputs');
      if(m.id==='sibling')assert(/synthetic/i.test(text),'External evaluation retains synthetic scope');
    }finally{await page.close();}
  }
  assert.deepEqual(report.errors,[],'navigation and guide checks');report.ok=true;
})().catch(error=>{report.errors.push(error.stack||String(error));console.error(error);process.exitCode=1;}).finally(async()=>{
  if(browser)await browser.close();if(server)await new Promise(resolve=>server.close(resolve));
  fs.writeFileSync(path.join(evidence,'report.json'),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify({ok:!!report.ok,modules:report.modules.length,pages:report.pages.length,guides:report.guides.length,external:report.external.length,evidence}));
});
