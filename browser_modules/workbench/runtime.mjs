const base=new URL('../../',import.meta.url);
export const encode=bytes=>{let s='';for(let i=0;i<bytes.length;i+=32768)s+=String.fromCharCode(...bytes.subarray(i,i+32768));return btoa(s);};
export const decode=text=>Uint8Array.from(atob(text),x=>x.charCodeAt(0));
const sha=async bytes=>[...new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))].map(x=>x.toString(16).padStart(2,'0')).join('');
const quote=x=>JSON.stringify(String(x));
const safePath=p=>{if(typeof p!=='string'||p.includes('\\')||p.includes('\0')||p.split('/').includes('..'))throw Error('Unsafe virtual file path.');return p;};
export class BrowserRuntime{
 constructor(progress=()=>{}){this.progress=(...args)=>{if(!this.closed)progress(...args);};this.pending=new Map();this.counter=0;this.packages=new Set();this.closed=false;}
 async python(operation,payload={}){
  if(this.closed)throw Error("Workspace reset.");
  if(!this.worker){this.worker=new Worker(new URL('./python-worker.mjs',import.meta.url),{type:'module'});this.worker.onmessage=async({data:m})=>{
   if(this.closed)return;if(m.kind==='progress'){this.progress(m.message);return;}
   if(m.kind==='r-command'){try{const result=await this.runRCommand(m.payload);if(!this.closed)this.worker.postMessage({kind:'r-response',id:m.id,result});}catch(e){if(!this.closed)this.worker.postMessage({kind:'r-response',id:m.id,error:String(e.message||e)});}return;}
   const p=this.pending.get(m.id);if(!p)return;this.pending.delete(m.id);if(m.error){const error=Error(m.error);error.diagnostics=m.diagnostics;p.reject(error);}else p.resolve(m.result);
  };this.worker.onerror=e=>{for(const p of this.pending.values())p.reject(Error(e.message||'Browser Python stopped. Reset the workspace.'));this.pending.clear();};}
  const id=++this.counter;return new Promise((resolve,reject)=>{this.pending.set(id,{resolve,reject});this.worker.postMessage({id,operation,payload});});
 }
 async r(){
  if(this.closed)throw Error("Workspace reset.");
  if(!this.rReady)this.rReady=(async()=>{this.progress('Loading R inside this browser…');const {WebR,ChannelType}=await import(new URL('shinylive/webr/webr.js',base));
   if(this.closed)throw Error('Workspace reset.');this.webR=new WebR({baseUrl:new URL('shinylive/webr/',base).href,channelType:ChannelType.PostMessage,interactive:false});await this.webR.init();if(this.closed){this.webR.close();throw Error('Workspace reset.');}
   this.packageIndex=await(await fetch(new URL('browser-runtime/packages.json',base))).json();
   await this.webR.evalRVoid('dir.create("/browser-library",showWarnings=FALSE); .libPaths(c("/browser-library",.libPaths())); options(webr.show_menu=FALSE)');return this.webR;
  })();return this.rReady;
 }
 async install(names){
  const r=await this.r(),order=new Set(),visit=name=>{if(order.has(name)||this.packages.has(name))return;const item=this.packageIndex[name];if(!item)return;order.add(name);item.dependencies.forEach(visit);};names.forEach(visit);
  const files=[];
  for(const name of order){const item=this.packageIndex[name];this.progress('Preparing browser R package: '+name);const response=await fetch(new URL(item.url,base));if(!response.ok)throw Error('Could not load R package '+name);const bytes=new Uint8Array(await response.arrayBuffer());if(await sha(bytes)!==item.sha256)throw Error('R package integrity mismatch: '+name);const p='/tmp/browser-package-'+name+'.tgz';await r.FS.writeFile(p,bytes);files.push(p);}
  if(files.length)await r.evalRVoid('for(p in c('+files.map(quote).join(',')+')) {utils::untar(p,exdir="/browser-library",tar="internal");unlink(p)}');
  for(const name of order)this.packages.add(name);
  const missing=await r.evalRString('paste(c('+names.map(quote).join(',')+')[!vapply(c('+names.map(quote).join(',')+'),requireNamespace,logical(1),quietly=TRUE)],collapse=", ")');
  if(missing)throw Error('Browser R dependencies are unavailable: '+missing);return r;
 }
 async writeTree(root,files){
  safePath(root);const r=await this.r(),parents=new Set([root]);
  for(const name of Object.keys(files)){safePath(name);if(name.startsWith('/'))throw Error('Expected a relative virtual file.');parents.add(root+'/'+name.split('/').slice(0,-1).join('/'));}
  await r.evalRVoid('invisible(lapply(c('+[...parents].map(quote).join(',')+'),dir.create,recursive=TRUE,showWarnings=FALSE))');
  for(const [name,content]of Object.entries(files))await r.FS.writeFile(root+'/'+name,typeof content==='string'?new TextEncoder().encode(content):content);
 }
 async readTree(root){
  const r=await this.r();safePath(root);const names=JSON.parse(await r.evalRString('jsonlite::toJSON(list.files('+quote(root)+',recursive=TRUE,all.files=TRUE,no..=TRUE),auto_unbox=FALSE)'));const files={};let total=0;
  for(const name of names){const bytes=await r.FS.readFile(root+'/'+name);total+=bytes.byteLength;if(total>256*1024*1024)throw Error('Result set exceeds the 256 MiB browser export limit. Run prespecified outputs in smaller batches.');files[name]=bytes;}return files;
 }
 async runAnalysis(module,built){
  const packages=module==='r_tlf'||module==='sas_tlf'?['jsonlite','dplyr','tidyr','stringr','purrr','tibble','rtables','ggplot2','ggrepel','patchwork','emmeans','lme4','lmerTest','broom','broom.mixed']:['jsonlite'];
  const r=await this.install(packages);const id='run-'+Date.now()+'-'+(++this.counter),root='/browser-runs/'+id,build=root+'/build',out=root+'/results';
  if(this.analysisRoot)await r.evalRVoid('unlink('+quote(this.analysisRoot)+',recursive=TRUE)');this.analysisRoot=root;
  await this.writeTree(build,built.files);await r.evalRVoid('dir.create('+quote(out)+',recursive=TRUE,showWarnings=FALSE)');
  this.progress('R is computing the selected outputs and preparing complete reports…');
  const plan={schema:1,module_id:module,build_root:build,run_root:out,source_root:build,build_id:id,run_id:id,approved:false,execution_mode:'browser webR; configured canonical sources'};
  await r.FS.writeFile(root+'/plan.json',new TextEncoder().encode(JSON.stringify(plan)));
  const passed=await r.evalRBoolean('local({source('+quote(build+'/toolkit_launcher/analysis_runner.R')+',local=TRUE);run_analysis('+quote(root+'/plan.json')+')})');
  const files=await this.readTree(out);for(const [name,bytes]of Object.entries(built.files))files['configuration/'+name]=new TextEncoder().encode(bytes);
  return {id,passed,files};
 }
 async runRCommand(request){
  const r=await this.install(['shiny','bslib','DT','jsonlite','ggplot2','testthat']);
  const {root,cwd,argv,files=[],deleted=[],release_root}=request;safePath(root);safePath(cwd);
  if(release_root){safePath(release_root);await r.evalRVoid('unlink('+quote(release_root)+',recursive=TRUE)');}
  if(deleted.length)await r.evalRVoid('unlink(c('+deleted.map(p=>quote(root+'/'+safePath(p))).join(',')+'),recursive=TRUE)');
  await this.writeTree(root,Object.fromEntries(files.map(f=>[f.path,decode(f.base64)])));
  await r.FS.writeFile('/tmp/browser-command.json',new TextEncoder().encode(JSON.stringify(request)));
  const before=JSON.parse(await r.evalRString('local({p<-list.files('+quote(root)+',recursive=TRUE,all.files=TRUE,no..=TRUE);jsonlite::toJSON(as.list(setNames(unname(tools::md5sum(file.path('+quote(root)+',p))),p)),auto_unbox=TRUE)})'));
  const answer=JSON.parse(await r.evalRString(`local({
   request <- jsonlite::fromJSON('/tmp/browser-command.json',simplifyVector=TRUE)
   old <- getwd(); old_options <- options(); on.exit({setwd(old);options(old_options)},add=TRUE)
   # Match native R's default nesting limit for testthat + Shiny; webR defaults to 400.
   options(expressions=5000)
   rm(list=ls(envir=.GlobalEnv,all.names=TRUE),envir=.GlobalEnv);setwd(request$cwd)
   args <- request$argv[-1L]; if(length(args)&&args[[1]]=='--vanilla') args<-args[-1L]
   inline <- length(args)>0L&&args[[1]]=='-e'; trailing <- if(inline) args[-c(1L,2L)] else args[-1L]
   assign('commandArgs',function(trailingOnly=FALSE) if(trailingOnly) trailing else c('R','--no-echo','--no-restore','--args',trailing),.GlobalEnv)
   exit <- function(save='no',status=0L,runLast=FALSE,...) stop(structure(list(message='',call=NULL,status=as.integer(status)),class=c('browser_exit','error','condition')))
   assign('quit',exit,.GlobalEnv);assign('q',exit,.GlobalEnv)
   profile <- file.path(request$root,request$profile); if(file.exists(profile)) sys.source(profile,.GlobalEnv)
   status <- 0L; err <- character()
   text <- capture.output(withCallingHandlers(tryCatch({if(inline) eval(parse(text=args[[2]]),.GlobalEnv) else sys.source(args[[1]],.GlobalEnv)},browser_exit=function(e){status<<-e$status},error=function(e){status<<-1L;err<<-c(err,conditionMessage(e))}),warning=function(w){err<<-c(err,paste('Warning:',conditionMessage(w)));invokeRestart('muffleWarning')}))
   jsonlite::toJSON(list(returncode=status,stdout=paste(c(text,err),collapse='\\n'),stderr=paste(err,collapse='\\n')),auto_unbox=TRUE)
  })`));
  const after=JSON.parse(await r.evalRString('local({p<-list.files('+quote(root)+',recursive=TRUE,all.files=TRUE,no..=TRUE);jsonlite::toJSON(as.list(setNames(unname(tools::md5sum(file.path('+quote(root)+',p))),p)),auto_unbox=TRUE)})'));answer.files=[];for(const [path,hash]of Object.entries(after))if(before[path]!==hash)answer.files.push({path,base64:encode(await r.FS.readFile(root+'/'+path))});answer.deleted=Object.keys(before).filter(p=>!(p in after));return answer;
 }
 close(){this.closed=true;this.worker?.terminate();try{Promise.resolve(this.webR?.close()).catch(()=>{});}catch{}for(const p of this.pending.values())p.reject(Error('Workspace reset.'));this.pending.clear();}
}

export function zipFiles(files){
 if(Object.keys(files).length>65535)throw Error('Too many ZIP entries.');
 const table=new Uint32Array(256);for(let i=0;i<256;i++){let c=i;for(let j=0;j<8;j++)c=(c&1)?0xedb88320^(c>>>1):c>>>1;table[i]=c;}
 const local=[],central=[];let offset=0,centralSize=0;const encoder=new TextEncoder();
 for(const [name,raw]of Object.entries(files)){safePath(name);if(name.startsWith('/'))throw Error('Unsafe ZIP path');const bytes=typeof raw==='string'?encoder.encode(raw):raw,label=encoder.encode(name);if(label.length>65535||bytes.length>0xffffffff||offset+bytes.length>0xffffffff)throw Error('ZIP size limit exceeded.');let crc=0xffffffff;for(const b of bytes)crc=table[(crc^b)&255]^(crc>>>8);crc=(crc^0xffffffff)>>>0;
  const h=new Uint8Array(30),d=new DataView(h.buffer);d.setUint32(0,0x04034b50,true);d.setUint16(4,20,true);d.setUint16(6,0x800,true);d.setUint16(12,0x21,true);d.setUint32(14,crc,true);d.setUint32(18,bytes.length,true);d.setUint32(22,bytes.length,true);d.setUint16(26,label.length,true);local.push(h,label,bytes);
  const c=new Uint8Array(46),v=new DataView(c.buffer);v.setUint32(0,0x02014b50,true);v.setUint16(4,20,true);v.setUint16(6,20,true);v.setUint16(8,0x800,true);v.setUint16(14,0x21,true);v.setUint32(16,crc,true);v.setUint32(20,bytes.length,true);v.setUint32(24,bytes.length,true);v.setUint16(28,label.length,true);v.setUint32(42,offset,true);central.push(c,label);centralSize+=c.length+label.length;offset+=h.length+label.length+bytes.length;
 }
 const end=new Uint8Array(22),e=new DataView(end.buffer);e.setUint32(0,0x06054b50,true);e.setUint16(8,Object.keys(files).length,true);e.setUint16(10,Object.keys(files).length,true);e.setUint32(12,centralSize,true);e.setUint32(16,offset,true);return new Blob([...local,...central,end],{type:'application/zip'});
}
export function download(blob,name){const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=name;document.body.append(a);a.click();setTimeout(()=>{a.remove();URL.revokeObjectURL(url);},1000);}
