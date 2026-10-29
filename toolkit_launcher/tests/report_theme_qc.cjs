'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),http=require('node:http');
const {pathToFileURL}=require('node:url');

async function themeState(page){
  return page.evaluate(()=>{
    let stored,storageError;
    if(window.__qcStorageAttempts!==undefined)storageError='disabled_by_qc';
    else try{stored=localStorage.getItem('bp-theme');}catch(error){storageError=error.name;}
    return {theme:document.documentElement.dataset.theme||null,stored,storageError,
      systemDark:matchMedia('(prefers-color-scheme: dark)').matches,ready:document.readyState,
      storageAttempts:window.__qcStorageAttempts||0,background:getComputedStyle(document.body).backgroundColor};
  });
}
async function assertTheme(page,theme,label){
  const state=await themeState(page);assert.equal(state.theme,theme,label+' '+JSON.stringify(state));return state;
}
async function selectTheme(page,theme,label){
  const state=await themeState(page),current=state.theme||(state.systemDark?'dark':'light');
  if(current!==theme)await page.locator('.theme-toggle').click();
  // Always exercise both directions, including when the initial theme matches.
  await page.locator('.theme-toggle').click();const away=await assertTheme(page,theme==='dark'?'light':'dark',label+' toggle away');
  await page.locator('.theme-toggle').click();const selected=await assertTheme(page,theme,label+' toggle back');
  assert.notEqual(selected.background,away.background,label+' light/dark backgrounds must differ');
}
async function staticReports(directory){
  const root=path.resolve(directory),types={'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.png':'image/png','.svg':'image/svg+xml','.js':'text/javascript; charset=utf-8'};
  const server=http.createServer((request,response)=>{
    try{
      const file=path.resolve(root,'.'+decodeURIComponent(new URL(request.url,'http://127.0.0.1').pathname)),relative=path.relative(root,file);
      if(request.method!=='GET'||relative.startsWith('..'+path.sep)||relative==='..'||path.isAbsolute(relative)||!fs.statSync(file).isFile())throw Error('Not found');
      response.writeHead(200,{'Content-Type':types[path.extname(file)]||'application/octet-stream','Cache-Control':'no-store'});response.end(fs.readFileSync(file));
    }catch{response.writeHead(404);response.end('Not found');}
  });
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
  return {url:file=>'http://127.0.0.1:'+server.address().port+'/'+path.relative(root,file).split(path.sep).map(encodeURIComponent).join('/'),
    close:()=>new Promise((resolve,reject)=>{server.close(error=>error?reject(error):resolve());server.closeAllConnections();})};
}

// File origins/storage are implementation-defined. Test downloaded-file controls
// directly; test saved preferences on a stable origin with the opposite OS theme.
// https://url.spec.whatwg.org/#origin
// https://html.spec.whatwg.org/multipage/webstorage.html#the-localstorage-attribute
async function checkDownloadedReportThemes({browser,files,directory,output,report}){
  const server=await staticReports(directory),counts={file_previews:0,persisted_themes:0,unavailable_storage:0};
  async function inspect(file,theme,width,phase,work){
    // Fresh pages/contexts avoid shared storage and compositor strips on resize.
    const systemTheme=phase==='persisted'?(theme==='dark'?'light':'dark'):theme;
    const preview=await browser.newPage({viewport:{width,height:width===390?844:1000},colorScheme:systemTheme});
    const stem='report-'+path.relative(directory,file).replace(/\.html$/,'').replaceAll(path.sep,'-')+'-'+theme+'-'+width;
    preview.on('pageerror',error=>report.errors.push(error.message));
    try{await work(preview,stem);}
    catch(error){
      const diagnostics={file,theme,width,phase,...await themeState(preview).catch(reason=>({inspectionError:String(reason)}))};
      fs.writeFileSync(path.join(output,stem+'-'+phase+'-failure.json'),JSON.stringify(diagnostics,null,2));
      await preview.screenshot({path:path.join(output,stem+'-'+phase+'-failure.png')}).catch(()=>{});
      throw error;
    }finally{await preview.close();}
  }
  try{
    for(const file of files){
      for(const theme of ['light','dark'])for(const width of [1440,390])await inspect(file,theme,width,'file',async(preview,stem)=>{
        await preview.goto(pathToFileURL(file).href);assert.equal(await preview.locator('.theme-toggle').count(),1,file);
        await selectTheme(preview,theme,file);
        assert.equal(await preview.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),true,file+' horizontal overflow');
        const name=stem+'.png';await preview.screenshot({path:path.join(output,name)});report.screenshots.push(name);counts.file_previews++;
      });
      for(const theme of ['light','dark'])await inspect(file,theme,1440,'persisted',async preview=>{
        await preview.goto(server.url(file));assert.equal(await preview.locator('.theme-toggle').count(),1,file);
        await selectTheme(preview,theme,file);const saved=await themeState(preview);assert.equal(saved.stored,theme,file+' saved preference');
        await preview.reload();await assertTheme(preview,theme,file+' persisted preference after reload');
        const state=await themeState(preview);assert.equal(state.stored,theme,file+' storage after reload');assert.equal(state.background,saved.background,file+' restored background');assert.equal(state.systemDark,theme!=='dark',file+' opposite system theme');counts.persisted_themes++;
      });
      for(const theme of ['light','dark'])await inspect(file,theme,390,'unavailable',async preview=>{
        await preview.addInitScript(()=>{window.__qcStorageAttempts=0;Object.defineProperty(window,'localStorage',{get(){window.__qcStorageAttempts++;throw new DOMException('Storage unavailable in QC','SecurityError');}});});
        await preview.goto(pathToFileURL(file).href);assert.equal(await preview.locator('.theme-toggle').count(),1,file);
        await selectTheme(preview,theme,file+' unavailable storage');
        assert.ok((await themeState(preview)).storageAttempts>=3,file+' exercised unavailable storage reads/writes');
        assert.equal(await preview.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),true,file+' unavailable-storage overflow');counts.unavailable_storage++;
      });
    }
  }finally{await server.close();}
  report.html_reports_checked=files.length;report.report_theme_checks=counts;
}
module.exports={checkDownloadedReportThemes};
