/* Browser controls for the local toolkit launcher. The public copy is a catalog only. */
'use strict';
(() => {
  const $ = id => document.getElementById(id);
  const root = document.documentElement;
  const themeKey = 'bp-theme', themeQuery = matchMedia('(prefers-color-scheme: light)');
  const savedTheme = () => { try { const t=localStorage.getItem(themeKey);return ['light','dark'].includes(t)?t:null; } catch { return null; } };
  const currentTheme = () => root.dataset.theme || (themeQuery.matches?'light':'dark');
  function applyTheme(value, save=false) {
    if(value) root.dataset.theme=value; else delete root.dataset.theme;
    const dark=currentTheme()==='dark', toggle=document.querySelector('.theme-toggle');
    toggle.setAttribute('aria-pressed',String(dark));toggle.title=dark?'Switch to light theme':'Switch to dark theme';
    if(save) try { localStorage.setItem(themeKey,value); } catch {}
  }
  document.querySelector('.theme-toggle').addEventListener('click',()=>applyTheme(currentTheme()==='dark'?'light':'dark',true));
  addEventListener('storage',event=>{if(event.key===themeKey)applyTheme(savedTheme());});
  themeQuery.addEventListener('change',()=>{if(!savedTheme())applyTheme(null);});
  applyTheme(savedTheme());

  const managed = root.dataset.managed === 'true' && ['127.0.0.1','localhost','[::1]'].includes(location.hostname);
  if(managed)for(const anchor of document.querySelectorAll('a[href^="../"]'))anchor.href='https://patrickiben.github.io/biometrics-ai-portfolio/'+anchor.getAttribute('href').slice(3);
  const tokenKey='toolkit-session-token', projectKey='toolkit-selected-project';
  const fragment=new URLSearchParams(location.hash.slice(1));
  let token=fragment.get('launch-token') || '';
  if(fragment.has('launch-token')) history.replaceState(null,'',location.pathname+location.search);
  if(managed) { try { if(token)sessionStorage.setItem(tokenKey,token);else token=sessionStorage.getItem(tokenKey)||''; } catch {} }
  else token='';
  let catalog=window.TOOLKIT_CATALOG || {modules:[]}, state=null, selected='', selectedTool=null, selectedAction=null, selectedConfig='';
  let refreshTimer=null, stopped=false, refreshWork=null, epoch=0;
  const isRunning=job=>['running','queued','starting'].includes(job.status);
  const modules=()=>catalog.modules||[];
  const selectedProject=()=>state?.projects?.find(p=>p.id===selected);
  const projectId=()=>{if(!selectedProject())throw Error('Create or select a private project first.');return selected;};
  const rememberProject=()=>{try{sessionStorage.setItem(projectKey,selected);}catch{}};
  const node=(tag,text,className)=>{const element=document.createElement(tag);if(text!==undefined)element.textContent=text;if(className)element.className=className;return element;};
  function message(text,error=false,focus=false) { $('message').textContent=text;$('message').hidden=!text;$('message').classList.toggle('error',error);if(text&&focus)$('message').focus(); }
  function toolNotice(text) {$('tool-status').textContent=text;$('tool-status').hidden=!text;}
  function safeURL(value,{local=false}={}) {
    if(typeof value!=='string'||!value.trim())return null;
    try {const url=new URL(value,location.href);if(!['http:','https:'].includes(url.protocol)&&!(location.protocol==='file:'&&url.protocol==='file:'))return null;if(local&&(!['127.0.0.1','localhost','[::1]'].includes(url.hostname)||url.protocol!=='http:'))return null;return url.href;}catch{return null;}
  }
  function documentURL(path) {
    if(!path)return null;
    return safeURL(/^https?:/.test(path)?path:(managed?'https://patrickiben.github.io/biometrics-ai-portfolio/':'../')+path.replace(/^\//,''));
  }
  function link(label,url,className='') { const a=node('a',label,className);a.href=url;a.target='_blank';a.rel='noopener noreferrer';return a; }
  function button(label,fn,{primary=false,disabled=false}={}) {const b=node('button',label,'btn'+(primary?' primary':''));b.type='button';b.disabled=disabled;b.addEventListener('click',fn);return b;}
  async function busy(container,fn) {
    const controls=container.matches?.('button')?[container]:Array.from(container.querySelectorAll('button,input,select'));
    const disabled=controls.map(control=>control.disabled);controls.forEach(control=>control.disabled=true);container.setAttribute('aria-busy','true');
    try{return await fn();}finally{controls.forEach((control,i)=>{if(control.isConnected)control.disabled=disabled[i];});container.removeAttribute('aria-busy');}
  }
  function disconnected(text='The local session has ended. Reopen Start Toolkit to reconnect.') {
    stopped=true;epoch++;clearTimeout(refreshTimer);token='';try{sessionStorage.removeItem(tokenKey);}catch{}
    $('local-shell').hidden=true;$('activity-panel').hidden=true;$('reconnect-panel').hidden=false;$('stop-launcher').hidden=true;$('activity-link').hidden=true;
    $('access-badge').textContent='Session closed';$('access-badge').className='badge neutral';
    for(const dialog of document.querySelectorAll('dialog[open]'))dialog.close();
    state=null;renderCatalog();message(text,true);
  }
  async function response(path,{body,method}={}) {
    if(!managed||!token||stopped)throw Error('Reopen Start Toolkit to connect to your private workspace.');
    const requestURL=new URL(path,location.href);
    if(requestURL.origin!==location.origin||!requestURL.pathname.startsWith('/api/'))throw Error('The launcher refused an unexpected download address.');
    const ownEpoch=epoch, headers={'X-Toolkit-Token':token,Accept:'application/json'};
    if(body!==undefined)headers['Content-Type']='application/json';
    const result=await fetch(requestURL.pathname+requestURL.search,{method:method||(body===undefined?'GET':'POST'),headers,body:body===undefined?undefined:JSON.stringify(body),credentials:'same-origin',cache:'no-store',redirect:'error'});
    if(ownEpoch!==epoch)throw Error('The earlier session response was discarded.');
    if(!result.ok){let data={};try{data=await result.json();}catch{}const error=Error(typeof data.error==='string'?data.error:`The request could not be completed (${result.status}).`);if(result.status===401||result.status===403)disconnected(error.message);throw error;}
    return result;
  }
  async function api(path,body) {const result=await response(path,{body});try{return await result.json();}catch{throw Error('The launcher returned an unreadable response. Refresh and try again.');}}
  async function download(path,name) {
    const result=await response(path), blob=await result.blob(), url=URL.createObjectURL(blob), anchor=document.createElement('a');
    anchor.href=url;anchor.download=name;anchor.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
  }
  async function act(fn,errorId) {try{if(errorId)$(errorId).textContent='';return await fn();}catch(error){if(errorId)$(errorId).textContent=error.message;else message(error.message,true,true);}}

  function renderCategories() {
    const current=$('category').value, categories=[...new Set(modules().map(m=>m.category).filter(Boolean))].sort();
    $('category').replaceChildren(new Option('All categories','all'),...categories.map(category=>new Option(category,category)));
    if(categories.includes(current))$('category').value=current;
  }
  function renderCatalog() {
    const search=$('search').value.trim().toLowerCase(), category=$('category').value;
    const visible=modules().filter(module=>(category==='all'||module.category===category)&&[module.title,module.summary,module.category,module.runtime,module.customization].join(' ').toLowerCase().includes(search));
    $('catalog-count').textContent=`${visible.length} of ${modules().length} tools`;
    $('catalog').replaceChildren();
    for(const module of visible) {
      const card=node('article',undefined,'tool-card');card.dataset.module=module.id;
      card.append(node('div',module.category||'Toolkit','kicker'),node('h3',module.title));
      const types=node('div',undefined,'type-line');
      const kinds={shiny:'Interactive R app',job:'Reproducible workflow',browser:'Browser workspace',templates:'Templates',reference:'Reference',external:'Separate runtime'};
      types.append(node('span',kinds[module.kind]||module.kind||'Tool'));
      if(module.runtime)types.append(node('span',module.runtime));
      card.append(types,node('p',module.summary));
      const actions=node('div',undefined,'actions');
      actions.append(button(state?'Open tool':'View details',()=>openTool(module.id),{primary:true}));
      const demo=safeURL(module.demo_url);if(demo)actions.append(link('Browser demo ↗',demo,'btn'));
      card.append(actions);$('catalog').append(card);
    }
    if(!visible.length)$('catalog').append(node('p',modules().length?'No tools match your search. Try another task or choose all categories.':'The tool catalog is not available. Open the setup guide to find each module.','catalog-empty'));
    $('catalog-failure').hidden=modules().length>0;
  }
  function renderRuntime() {
    $('runtime-list').replaceChildren();
    const runtime=state.runtime||{};
    for(const [id,item] of Object.entries(runtime)) {
      if(!['python','r','quarto'].includes(id))continue;
      if(!item||typeof item!=='object')continue;
      const row=node('div',undefined,'runtime-row'), description=node('div');
      description.append(node('strong',item.label||({r:'R / Rscript',python:'Python',quarto:'Quarto'}[id]||id)));
      description.append(node('p',item.message||item.version||(item.available?'Ready to use':'Install this runtime to use its tools')));
      if(item.path){const path=node('p',item.path,'path');description.append(path);}
      const badge=node('span',item.available?'Available':'Not found','badge'+(item.available?'':' warn'));row.append(description,badge);$('runtime-list').append(row);
    }
    if(!$('runtime-list').children.length)$('runtime-list').append(node('p','Runtime details will appear after a setup check.','small'));
    if(!$('runtime-settings').open){$('r-path').value=state.settings?.r_path||'';$('quarto-path').value=state.settings?.quarto_path||'';}
  }
  function renderProjects() {
    const projects=state.projects||[];
    if(!projects.some(project=>project.id===selected))selected=projects[0]?.id||'';
    rememberProject();$('project-select').replaceChildren(...projects.map(project=>new Option(project.name,project.id)));$('project-select').value=selected;
    $('project-empty').hidden=projects.length>0;$('project-controls').hidden=!projects.length;$('export-help').hidden=!projects.length;
    $('project-meta').replaceChildren();const project=selectedProject();
    if(project){$('project-meta').append(node('strong',project.name),node('span',project.path||'Private project · Synthetic examples copied at creation','path'));}
    const base=state.projects_root||state.workspace_root||'';$('projects-location').textContent=base?`Projects folder: ${base}`:'';
    $('project-destination').textContent=base?`Saved in ${base}`:'Saved in the launcher’s private projects folder, outside your toolkit download.';
  }
  function jobTitle(job) {
    if(job.label)return job.label;
    for(const module of modules()){const action=(module.actions||[]).find(action=>action.id===job.action_id);if(action)return `${module.title} · ${action.label}`;}
    return job.action_id||'Toolkit activity';
  }
  function renderJobs() {
    const jobs=state.jobs||[], opened=new Set(Array.from($('jobs').querySelectorAll('details[open]')).map(detail=>detail.dataset.job));
    $('jobs').replaceChildren();$('activity-count').textContent=jobs.length?`${jobs.length} ${jobs.length===1?'activity':'activities'}`:'';
    if(!jobs.length){$('jobs').append(node('p','No activity yet. Choose a tool to check its setup or start a run.','activity-empty'));return;}
    for(const job of [...jobs].reverse()) {
      const item=node('article',undefined,'job');item.dataset.job=job.id;
      const head=node('div',undefined,'job-head'), names={running:'Running',queued:'Queued',starting:'Starting',succeeded:'Finished',failed:'Failed',stopped:'Stopped'};
      head.append(node('strong',jobTitle(job)),node('span',names[job.status]||job.status,'badge'+(job.status==='failed'?' error':job.status==='stopped'?' neutral':isRunning(job)?' warn':'')));item.append(head);
      const project=state.projects?.find(project=>project.id===job.project_id);
      item.append(node('p',[project?.name,job.message,job.error].filter(Boolean).join(' · '),'job-meta'));
      if(isRunning(job)){const progress=node('div',undefined,'progress');progress.setAttribute('role','progressbar');progress.setAttribute('aria-label','Activity in progress');progress.append(node('span'));item.append(progress);}
      const controls=node('div',undefined,'actions');
      if(isRunning(job))controls.append(button('Stop',event=>busy(event.currentTarget,()=>act(async()=>{await api(`/api/jobs/${encodeURIComponent(job.id)}/stop`,{});await refresh();}))));
      const open=safeURL(job.url,{local:true});if(open)controls.append(link('Open running tool ↗',open,'btn primary'));
      if(controls.childElementCount)item.append(controls);
      const details=node('details');details.dataset.job=job.id;details.open=opened.has(job.id)||job.status==='failed';details.append(node('summary','Show run log'),node('pre',Array.isArray(job.log)?job.log.join('\n'):job.log||'Waiting for the first log message…','log'));item.append(details);
      if(job.outputs?.length){const outputs=node('div',undefined,'outputs');for(const output of job.outputs){const label=output.label||output.path||'Download output';const b=button(label,event=>busy(event.currentTarget,()=>act(()=>download(output.url||`/api/files?${new URLSearchParams({project_id:job.project_id,path:output.path})}`,output.path?.split('/').pop()||'output'))));outputs.append(b);}item.append(outputs);}
      $('jobs').append(item);
    }
  }
  function refresh(force=false) {
    if(stopped)return Promise.resolve();
    if(refreshWork)return force?refreshWork.then(()=>refresh(true)):refreshWork;
    refreshWork=(async()=>{state=await api('/api/state'+(force?'?refresh=1':''));catalog=state.catalog||catalog;renderCategories();renderRuntime();renderProjects();renderCatalog();renderJobs();})().finally(()=>{refreshWork=null;});
    return refreshWork;
  }
  function scheduleRefresh() {
    clearTimeout(refreshTimer);if(stopped)return;
    refreshTimer=setTimeout(async()=>{if(!document.hidden)await act(refresh);scheduleRefresh();},2500);
  }
  function createProject() {$('project-error').textContent='';$('project-form').reset();$('project-dialog').showModal();$('project-name').focus();}
  function addDetail(title,value,{list=false}={}) {
    if(!value||Array.isArray(value)&&!value.length)return;
    const block=node('div');block.append(node('h3',title));
    if(list){const ul=node('ul');for(const item of Array.isArray(value)?value:[value])ul.append(node('li',typeof item==='string'?item:item.label||item.path));block.append(ul);}
    else block.append(node('p',Array.isArray(value)?value.join(' '):value));
    $('tool-details').append(block);
  }
  function actionDetails(action) {
    const definitions=state?.actions||state?.action_catalog||{};
    const definition=Array.isArray(definitions)?definitions.find(item=>item.id===action.id)||{}:definitions[action.id]||{};
    return {...definition,...action};
  }
  function fieldSchema(action) {
    const fields=[...(action.fields||action.options_schema||action.options||[])];
    if(action.install||action.id.endsWith('.install'))fields.push({id:'allow_install',label:'Download and install the required packages',type:'checkbox',default:false,required:true,description:action.description||'Installs packages into this private project. An internet connection is required.'});
    return fields;
  }
  function makeFields(container,fields,values={}) {
    container.replaceChildren();
    for(const field of fields) {
      const wrapper=node('div',undefined,'field'+(field.type==='textarea'?' wide':'')), id=`${container.id}-${field.id||field.name}`, label=node('label',field.label||field.id||field.name);label.htmlFor=id;
      let input;if(field.type==='select'){input=node('select');for(const option of field.choices||field.options||[])input.append(new Option(typeof option==='string'?option:option.label,typeof option==='string'?option:option.value));}
      else {input=node(field.type==='textarea'?'textarea':'input');if(field.type!=='textarea')input.type=['number','checkbox','password'].includes(field.type)?field.type:'text';}
      input.id=id;input.name=field.id||field.name;input.required=!!field.required;
      if(input.type==='number')input.step=field.step??'any';
      if(input.type==='checkbox')input.checked=!!(values[input.name]??field.default);else input.value=values[input.name]??field.default??'';
      for(const key of ['min','max','step','placeholder'])if(field[key]!==undefined)input.setAttribute(key,field[key]);
      if(input.type==='checkbox')wrapper.className+=' check';wrapper.append(label,input);if(field.description||field.help)wrapper.append(node('p',field.description||field.help,'help'));container.append(wrapper);
    }
  }
  function fieldValues(container) {const values={};for(const input of container.querySelectorAll('input,select,textarea'))values[input.name]=input.type==='checkbox'?input.checked:input.type==='number'?Number(input.value):input.value;return values;}
  async function fileAction(path) {await api('/api/files/open',{project_id:projectId(),path});toolNotice('Opened the private project file in your computer’s default application.');}
  async function uploadInput(input,file) {
    if(!file)throw Error('Choose a replacement file first.');
    if(file.size>16*1024*1024)throw Error('Choose a file smaller than 16 MB. Larger files can be copied into the project folder.');
    const content=await new Promise((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve(String(reader.result).split(',')[1]);reader.onerror=()=>reject(Error('The selected file could not be read.'));reader.readAsDataURL(file);});
    await api('/api/files',{project_id:projectId(),path:input.path,content_base64:content});toolNotice(`Replaced ${input.label||input.path} in ${selectedProject().name}.`);
  }
  function renderToolProject(module) {
    const area=$('tool-project');area.replaceChildren();area.hidden=!state;
    if(!state)return;
    const project=selectedProject();
    if(!project){area.append(node('p','Create a private project to use setup, run and input controls.','small'),button('Create project from examples',createProject,{primary:true}));return;}
    area.append(node('h3',`Project: ${project.name}`));
    const inputs=module.inputs||[];
    if(inputs.length){area.append(node('p','Download a template, edit it in its usual application, or choose a file to replace it in this project.','help'));const list=node('div',undefined,'file-list');
      for(const input of inputs){const row=node('div',undefined,'file-row'), description=node('div');description.append(node('strong',input.label||input.path),node('div',input.path,'path'));if(input.description)description.append(node('p',input.description,'help'));row.append(description);
        const controls=node('div',undefined,'actions');controls.append(button('Open / edit',event=>busy(event.currentTarget,()=>act(()=>fileAction(input.path),'tool-error'))),button('Download',event=>busy(event.currentTarget,()=>act(()=>download(`/api/files?${new URLSearchParams({project_id:project.id,path:input.path})}`,input.path.split('/').pop()),'tool-error'))));
        const chooser=node('input');chooser.type='file';chooser.setAttribute('aria-label',`Choose replacement for ${input.label||input.path}`);chooser.style.fontSize='12px';
        const upload=button('Replace in project',async event=>{await busy(row,()=>act(async()=>{await uploadInput(input,chooser.files[0]);chooser.value='';},'tool-error'));upload.disabled=!chooser.files.length;},{disabled:true});chooser.addEventListener('change',()=>upload.disabled=!chooser.files.length);
        const picker=node('div',undefined,'input-row');picker.style.width='100%';picker.append(chooser,upload);row.append(controls,picker);list.append(row);
      }area.append(list);
    }
  }
  function openTool(id) {
    const module=modules().find(module=>module.id===id);if(!module)return;selectedTool=module;selectedAction=null;
    $('tool-title').textContent=module.title;$('tool-summary').textContent=module.summary;$('tool-error').textContent='';$('run-error').textContent='';$('configure-error').textContent='';toolNotice('');$('tool-details').replaceChildren();$('tool-actions').replaceChildren();$('run-form').hidden=true;$('configure-form').hidden=true;
    addDetail('What you can adapt',module.customization);addDetail('Saving your work',module.persistence);addDetail('Scope and limits',module.limits);addDetail('Outputs',module.outputs,{list:true});
    const docs=node('div');docs.append(node('h3','Guides & reference'));const list=node('ul');
    for(const doc of module.docs||[]){const url=documentURL(doc.path);if(url){const li=node('li');li.append(link(doc.label||doc.path,url));list.append(li);}}
    const demo=safeURL(module.demo_url);if(demo){const li=node('li');li.append(link('Open browser demo ↗',demo));list.append(li);}docs.append(list);if(list.childElementCount)$('tool-details').append(docs);
    renderToolProject(module);
    for(const raw of module.actions||[]){const action=actionDetails(raw);
      if(action.type==='open'){const path=action.path;if(/^https?:/.test(path||'')){const url=safeURL(path);if(url)$('tool-actions').append(link(action.label+' ↗',url,'btn'));}else if(state&&path)$('tool-actions').append(button(action.label,event=>busy(event.currentTarget,()=>act(()=>fileAction(path),'tool-error')),{disabled:!selectedProject()}));}
      else if(!state)continue;
      else if(action.type==='configure'){$('tool-actions').append(button(action.label,event=>busy(event.currentTarget,()=>act(async()=>{
        selectedConfig=action.module_id||action.id;const schema=state.configuration?.[selectedConfig]||module.configuration||{};
        const fields=action.fields||module.config_fields||schema.fields||[];
        if(!fields.length){$('tool-error').textContent='Use Open / edit on the configuration file above, then save it in the private project.';return;}
        const saved=await api(`/api/configure?${new URLSearchParams({project_id:projectId(),module_id:selectedConfig})}`);
        $('configure-form').hidden=false;$('configure-form').querySelector('.help').textContent=schema.description||'Saved only in the selected private project.';
        makeFields($('configure-fields'),fields,saved.values||{});$('configure-form').scrollIntoView({block:'nearest'});
      },'tool-error')),{disabled:!selectedProject()}));}
      else if(['job','tracker'].includes(action.type)){$('tool-actions').append(button(action.label,event=>{const fields=fieldSchema(action);if(fields.length){selectedAction=action;$('run-form').hidden=false;makeFields($('run-fields'),fields);$('run-submit').textContent=action.label;$('run-form').scrollIntoView({block:'nearest'});}else busy(event.currentTarget,()=>act(()=>startAction(action,{}),'tool-error'));},{primary:/start|run|launch/i.test(action.id),disabled:!selectedProject()}));}
    }
    if(!$('tool-dialog').open)$('tool-dialog').showModal();
  }
  async function startAction(action,options) {
    const result=await api('/api/actions',{project_id:projectId(),action_id:action.id,options});await refresh();
    message(`${action.label} started. Follow progress in Activity & outputs.`);$('tool-dialog').close();$('activity-panel').scrollIntoView({behavior:'smooth',block:'start'});
    const id=result.id||result.job?.id;if(id){const detail=Array.from($('jobs').querySelectorAll('details')).find(detail=>detail.dataset.job===id);if(detail)detail.open=true;}
  }

  $('search').addEventListener('input',renderCatalog);$('category').addEventListener('change',renderCatalog);
  for(const close of document.querySelectorAll('[data-close]'))close.addEventListener('click',()=>$(close.dataset.close).close());
  $('new-project').addEventListener('click',createProject);
  $('project-select').addEventListener('change',()=>{selected=$('project-select').value;rememberProject();renderProjects();if($('tool-dialog').open&&selectedTool)openTool(selectedTool.id);});
  $('project-form').addEventListener('submit',event=>{event.preventDefault();const submit=$('create-project');submit.textContent='Copying project files…';busy($('project-form'),()=>act(async()=>{const result=await api('/api/projects',{name:$('project-name').value.trim()});selected=result.id||result.project?.id||'';rememberProject();await refresh();$('project-dialog').close();if($('tool-dialog').open&&selectedTool)openTool(selectedTool.id);message('Private project created from the synthetic examples. Choose a tool to review and replace its inputs.',false,true);},'project-error')).finally(()=>submit.textContent='Create project from examples');});
  $('refresh-status').addEventListener('click',event=>busy(event.currentTarget,()=>act(async()=>{await refresh(true);message('Computer and project status refreshed.');})));
  $('open-folder').addEventListener('click',event=>busy(event.currentTarget,()=>act(async()=>{await api(`/api/projects/${encodeURIComponent(projectId())}/open`,{});message('Opened your private project folder.');})));
  $('export-project').addEventListener('click',event=>busy(event.currentTarget,()=>act(()=>download(`/api/projects/${encodeURIComponent(projectId())}/export`,`${selectedProject().name}.zip`))));
  for(const picker of document.querySelectorAll('[data-pick]'))picker.addEventListener('click',()=>busy(picker,()=>act(async()=>{const result=await api('/api/pick-file',{kind:picker.dataset.pick});if(result.path)$(picker.dataset.pick+'-path').value=result.path;},'settings-error')));
  $('settings-form').addEventListener('submit',event=>{event.preventDefault();busy($('settings-form'),()=>act(async()=>{await api('/api/settings',{r_path:$('r-path').value.trim(),quarto_path:$('quarto-path').value.trim()});await refresh();message('Runtime locations saved.');},'settings-error'));});
  $('run-form').addEventListener('submit',event=>{event.preventDefault();if(!selectedAction)return;busy($('run-form'),()=>act(()=>startAction(selectedAction,fieldValues($('run-fields'))),'run-error'));});
  $('configure-form').addEventListener('submit',event=>{event.preventDefault();busy($('configure-form'),()=>act(async()=>{await api('/api/configure',{project_id:projectId(),module_id:selectedConfig,values:fieldValues($('configure-fields'))});toolNotice('Configuration saved in your private project.');},'configure-error'));});
  $('stop-launcher').addEventListener('click',event=>busy(event.currentTarget,()=>act(async()=>{await api('/api/stop',{});disconnected('The local launcher is closed. Your project files are saved. Reopen Start Toolkit when you want to continue.');$('message').classList.remove('error');})));
  async function boot() {
    renderCategories();renderCatalog();
    if(!managed)return;
    $('static-panel').hidden=true;
    if(!token){$('reconnect-panel').hidden=false;return;}
    $('loading').hidden=false;
    try {try{selected=sessionStorage.getItem(projectKey)||'';}catch{}await refresh();$('local-shell').hidden=false;$('activity-panel').hidden=false;$('stop-launcher').hidden=false;$('activity-link').hidden=false;$('access-badge').textContent='Private · This computer';$('access-badge').className='badge';scheduleRefresh();}
    catch(error){if(!stopped){$('reconnect-panel').hidden=false;message(error.message,true);}}
    finally{$('loading').hidden=true;}
  }
  boot();
})();
