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
    const controls=container.matches?.('button')?[container]:Array.from(container.querySelectorAll('button,input,select,textarea'));
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
      const demo=safeURL(module.demo_url);if(demo)actions.append(link((module.browser_label||'Browser demo')+' ↗',demo,'btn'));
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
      if(job.outputs?.length){const outputs=node('div',undefined,'outputs');for(const output of job.outputs){const label=output.label||output.path||'Download output';const b=button(label,event=>busy(event.currentTarget,()=>act(()=>download(output.url||`/api/files?${new URLSearchParams({project_id:job.project_id,path:output.path})}`,output.path?.split('/').pop()||'output'))));outputs.append(b);if(job.analysis&&output.path?.endsWith('/analysis_report.html'))outputs.append(button('Open analysis report',event=>busy(event.currentTarget,()=>act(()=>api('/api/files/open',{project_id:job.project_id,path:output.path})))));}item.append(outputs);}
      if(job.analysis)item.append(node('p','This run belongs to one saved package version. Automated QC completion does not grant scientific approval.','small'));
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
      else {input=node(field.type==='textarea'?'textarea':'input');if(field.type!=='textarea')input.type=['number','checkbox','password','date'].includes(field.type)?field.type:'text';}
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
  let guided=null, guidedSequence=0;
  const guidedFields=()=>guided?.schema.steps.flatMap(step=>step.fields||[])||[];
  const guidedSteps=()=>guided?.steps||[];
  const guidedCurrent=()=>guidedSteps()[guided?.step||0];
  function guidedDefaults(schema,values) {
    const result={};
    for(const step of schema.steps||[])for(const field of step.fields||[])result[field.id]=field.default??(['multiselect','template-select'].includes(field.type)?[]:field.type==='checkbox'?false:'');
    return {...result,...values,columns:{...(values?.columns||{})}};
  }
  function guidedSignature(){return JSON.stringify(guided.values);}
  function guidedChanged() {
    if(!guided)return;guided.validated='';guided.reviewed=false;$('guided-review-check').checked=false;$('guided-generate').disabled=true;
    if(guided.report)$('guided-status').textContent='Setup changed. Preview and validate again before generating.';
  }
  function captureGuided() {
    if(!guided)return;
    for(const wrapper of $('guided-fields').querySelectorAll('[data-guide-field]')){
      const field=wrapper.dataset.guideField,kind=wrapper.dataset.kind;
      if(['multiselect','template-select'].includes(kind))guided.values[field]=Array.from(wrapper.querySelectorAll('input[data-choice]:checked')).map(input=>input.value);
      else {const input=wrapper.querySelector('[data-guide-control]');if(input)guided.values[field]=input.type==='checkbox'?input.checked:input.type==='number'&&input.value!==''?Number(input.value):input.value;}
    }
    for(const input of $('guided-inputs').querySelectorAll('select[data-slot]')){
      guided.values.columns[input.dataset.slot]||={};guided.values.columns[input.dataset.slot][input.dataset.column]=input.value;
    }
    for(const slot of guided.schema.inputs||[])if(slot.dynamic_columns_fields?.length){const allowed=new Set(guidedColumns(slot).map(column=>typeof column==='string'?column:column.id));for(const key of Object.keys(guided.values.columns[slot.id]||{}))if(!allowed.has(key))delete guided.values.columns[slot.id][key];}
  }
  function guideOptions(field) {
    const entries=field.options_by_design?field.options_by_design[guided.values[field.depends_on||'design']]||[]:field.options||field.choices||[];
    return entries.map(option=>typeof option==='string'?{value:option,label:option}:option);
  }
  function renderGuidedFields(fields) {
    const area=$('guided-fields');area.replaceChildren();
    for(const field of fields||[]){
      const kind=field.type||'text',multiple=['multiselect','template-select'].includes(kind);
      const wrapper=node(multiple?'fieldset':'div',undefined,multiple?'guided-choices wide':'field'+(kind==='textarea'?' wide':''));
      wrapper.dataset.guideField=field.id;wrapper.dataset.kind=kind;
      const id='guided-field-'+field.id;
      if(multiple){
        wrapper.append(node('legend',(field.label||field.id)+(field.required?' *':'')));
        if(field.description)wrapper.append(node('p',field.description,'help'));
        const options=guideOptions(field),list=node('div',undefined,'guided-choice-list'),selectedValues=new Set(guided.values[field.id]||[]);
        const search=node('input');search.type='search';search.placeholder='Find an output';search.setAttribute('aria-label','Find '+(field.label||'outputs').toLowerCase());
        if(options.length>10)wrapper.append(search);
        for(const option of options){
          const label=node('label',undefined,'guided-choice'),input=node('input');input.type='checkbox';input.value=String(option.value);input.dataset.choice='true';input.checked=selectedValues.has(option.value);
          label.append(input,node('span',option.label||option.value));label.dataset.search=[option.label,option.value].join(' ').toLowerCase();list.append(label);
          input.addEventListener('change',()=>{captureGuided();guidedChanged();});
        }
        if(!options.length)wrapper.append(node('p','Choose the study design first to see its available outputs.','help'));
        const tools=node('div',undefined,'guided-choice-tools');
        if(options.length){tools.append(button('Select shown',()=>{for(const label of list.children)if(!label.hidden)label.querySelector('input').checked=true;captureGuided();guidedChanged();}),button('Clear selection',()=>{for(const input of list.querySelectorAll('input'))input.checked=false;captureGuided();guidedChanged();}));wrapper.append(tools);}
        search.addEventListener('input',()=>{const query=search.value.toLowerCase();for(const label of list.children)label.hidden=!label.dataset.search.includes(query);});
        wrapper.append(list);
      }else{
        const label=node('label',(field.label||field.id)+(field.required?' *':''));label.htmlFor=id;
        let input;
        if(kind==='select'){input=node('select');for(const option of guideOptions(field))input.append(new Option(option.label||option.value,String(option.value)));}
        else {input=node(kind==='textarea'?'textarea':'input');if(kind!=='textarea')input.type=['number','checkbox','password','date'].includes(kind)?kind:'text';}
        input.id=id;input.name=field.id;input.dataset.guideControl='true';input.required=!!field.required;
        if(input.type==='checkbox')input.checked=!!guided.values[field.id];else input.value=guided.values[field.id]??'';
        for(const key of ['min','max','step','placeholder','maxlength'])if(field[key]!==undefined)input.setAttribute(key,field[key]);
        if(input.type==='number'&&field.step===undefined)input.step='any';
        if(kind==='checkbox')wrapper.className+=' check';
        wrapper.append(label,input);if(field.description){const help=node('p',field.description,'help');help.id=id+'-help';input.setAttribute('aria-describedby',help.id);wrapper.append(help);}
        input.addEventListener('input',()=>{captureGuided();guidedChanged();});
        input.addEventListener('change',()=>{
          captureGuided();guidedChanged();
          let dependent=false;for(const candidate of guidedFields())if(candidate.depends_on===field.id){guided.values[candidate.id]=[];dependent=true;}
          if(dependent){renderGuidedStep();$('guided-status').textContent='Study selection changed. Choose the outputs for this design.';}
        });
      }
      area.append(wrapper);
    }
  }
  function guidedPreviewTable(meta) {
    if(!Array.isArray(meta.preview)||!meta.preview.length)return null;
    const box=node('details'),summary=node('summary','Preview first rows');box.append(summary);
    const wrap=node('div',undefined,'guided-table-wrap');wrap.tabIndex=0;wrap.setAttribute('role','region');wrap.setAttribute('aria-label','CSV preview');
    const table=node('table',undefined,'guided-table'),columns=(meta.columns||[]).slice(0,12),head=node('tr');
    table.append(node('caption','First '+Math.min(5,meta.preview.length)+' rows'+(meta.columns.length>12?' · first 12 columns':'')));
    for(const column of columns){const th=node('th',column);th.scope='col';head.append(th);}const thead=node('thead');thead.append(head);table.append(thead);
    const tbody=node('tbody');
    for(const row of meta.preview.slice(0,5)){const tr=node('tr');for(const [index,column] of columns.entries())tr.append(node('td',String(Array.isArray(row)?row[index]??'':row[column]??'')));tbody.append(tr);}
    table.append(tbody);wrap.append(table);box.append(wrap);return box;
  }
  function guidedColumns(slot) {
    const columns=[...(slot.columns||[])],known=new Set(columns.map(raw=>typeof raw==='string'?raw:raw.id));
    for(const field of slot.dynamic_columns_fields||[]){
      const codes=String(guided.values[field]||'').split(',').map(value=>value.trim().toUpperCase()).filter(value=>/^[A-Z][A-Z0-9_]{0,39}$/.test(value)).slice(0,100);
      for(const code of codes)if(!known.has(code)){known.add(code);columns.push({id:code,label:code+' · study-specific baseline',type:field==='baseline_continuous'?'number':'text',required:true});}
    }
    return columns;
  }
  function suggestMappings(slot,columns) {
    guided.values.columns[slot.id]||={};const mapping=guided.values.columns[slot.id];
    for(const raw of guidedColumns(slot)){
      const column=typeof raw==='string'?{id:raw}:raw;
      if(Object.hasOwn(mapping,column.id)&&(mapping[column.id]===''||columns.includes(mapping[column.id])))continue;
      const exact=columns.includes(column.id)?column.id:null,folded=columns.filter(name=>name.toLowerCase()===column.id.toLowerCase());
      mapping[column.id]=exact||(folded.length===1?folded[0]:'');
    }
  }
  async function uploadGuided(slot,file) {
    if(!file)throw Error('Choose a CSV file first.');
    if(file.size>16*1024*1024)throw Error('Choose a CSV file smaller than 16 MB.');
    if(!/\.csv$/i.test(file.name))throw Error('Choose a UTF-8 CSV file.');
    captureGuided();const own=guided,sequence=guidedSequence;
    own.pendingUploads=(own.pendingUploads||0)+1;guidedChanged();updateGuidedGenerate();
    try {
      const content=await new Promise((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve(String(reader.result).split(',')[1]);reader.onerror=()=>reject(Error('The selected file could not be read.'));reader.readAsDataURL(file);});
      const data=await api('/api/template-input',{project_id:own.projectId,module_id:own.moduleId,slot:slot.id,filename:file.name,content_base64:content});
      if(sequence!==guidedSequence||guided!==own)return;
      guided.inputs=data.inputs||{...guided.inputs,[slot.id]:data.input};suggestMappings(slot,guided.inputs[slot.id]?.columns||[]);
      guidedChanged();renderGuidedStep();$('guided-status').textContent='Added '+file.name+'. Header matches were suggested; review the column mappings before generating.';
    } finally {
      own.pendingUploads--;if(guided===own)updateGuidedGenerate();
    }
  }
  async function useGuidedExample(slot) {
    const own=guided,sequence=guidedSequence;
    const result=await response('/api/files?'+new URLSearchParams({project_id:own.projectId,path:slot.example_path}));
    const blob=await result.blob();
    if(sequence!==guidedSequence||guided!==own)return;
    await uploadGuided(slot,new File([blob],slot.example_path.split('/').pop(),{type:'text/csv'}));
  }
  function selectedGuidedInputs() {
    const selectionFields=guidedFields().filter(field=>['select','multiselect','template-select'].includes(field.type));
    const slots=new Set();let hasMetadata=false;
    for(const field of selectionFields){
      const value=guided.values[field.id],selected=new Set(Array.isArray(value)?value:[value]);
      for(const option of guideOptions(field))if(Array.isArray(option.inputs)){hasMetadata=true;if(selected.has(option.value))for(const slot of option.inputs)slots.add(slot);}
    }
    return hasMetadata?(guided.schema.inputs||[]).filter(slot=>slots.has(slot.id)):guided.schema.inputs||[];
  }
  function renderGuidedInputs() {
    const area=$('guided-inputs');area.replaceChildren();if(guidedCurrent().id!=='inputs')return;
    area.append(node('p','Choose the CSV files for this study. Map each template column to its source column; header matches are suggestions for your review.','help'));
    const slots=selectedGuidedInputs();if(!slots.length)area.append(node('p','Choose checks or outputs first to see their required input files.','note'));
    for(const [index,slot] of slots.entries()){
      const meta=guided.inputs[slot.id],details=node('details',undefined,'guided-input');details.dataset.slot=slot.id;details.open=!!meta||index===0;
      const summary=node('summary',slot.label||slot.id);summary.append(node('span',meta?(meta.filename||slot.id+'.csv')+' · '+meta.rows+' rows · '+meta.columns.length+' columns':'No input added'));details.append(summary);
      const body=node('div',undefined,'guided-input-body');if(slot.description)body.append(node('p',slot.description,'help'));
      const picker=node('input');picker.type='file';picker.accept='.csv,text/csv';picker.setAttribute('aria-label','Choose CSV for '+(slot.label||slot.id));
      const replace=button(meta?'Replace CSV':'Add CSV',event=>busy($('guided-dialog'),()=>act(()=>uploadGuided(slot,picker.files[0]),'guided-error')).finally(updateGuidedGenerate),{disabled:true});
      picker.addEventListener('change',()=>replace.disabled=!picker.files.length);
      const controls=node('div',undefined,'actions');controls.append(picker,replace);
      if(meta?.path)controls.append(button('Download input',event=>busy(event.currentTarget,()=>act(()=>download('/api/files?'+new URLSearchParams({project_id:guided.projectId,path:meta.path}),meta.filename||slot.id+'.csv'),'guided-error'))));
      body.append(controls);
      if(slot.template_path||slot.example_path){
        const examples=node('div',undefined,'actions');
        if(slot.template_path)examples.append(button('Download template',event=>busy(event.currentTarget,()=>act(()=>download('/api/files?'+new URLSearchParams({project_id:guided.projectId,path:slot.template_path}),slot.template_path.split('/').pop()),'guided-error'))));
        if(slot.example_path){
          examples.append(button('Download synthetic example',event=>busy(event.currentTarget,()=>act(()=>download('/api/files?'+new URLSearchParams({project_id:guided.projectId,path:slot.example_path}),slot.example_path.split('/').pop()),'guided-error'))));
          examples.append(button('Use synthetic example',()=>busy($('guided-dialog'),()=>act(()=>useGuidedExample(slot),'guided-error')).finally(updateGuidedGenerate)));
        }
        body.append(examples,node('p','Synthetic examples are fictional. Using an example replaces this input through the usual upload checks; choose and review study settings separately.','help'));
      }
      if(meta){
        const mappings=node('div',undefined,'guided-mapping');suggestMappings(slot,meta.columns||[]);
        for(const raw of guidedColumns(slot)){
          const column=typeof raw==='string'?{id:raw}:raw,field=node('div',undefined,'field'),id='guided-map-'+slot.id+'-'+column.id,label=node('label',(column.label||column.id)+(column.required?' *':''));
          label.htmlFor=id;const select=node('select');select.id=id;select.dataset.slot=slot.id;select.dataset.column=column.id;select.append(new Option('Choose source column',''),...meta.columns.map(name=>new Option(name,name)));select.value=guided.values.columns[slot.id][column.id]||'';
          select.addEventListener('change',()=>{captureGuided();guidedChanged();});field.append(label,select);if(column.description)field.append(node('p',column.description,'help'));mappings.append(field);
        }
        body.append(mappings);const preview=guidedPreviewTable(meta);if(preview)body.append(preview);
        if(meta.sha256)body.append(node('p','Input fingerprint: '+meta.sha256,'path'));
      }
      details.append(body);area.append(details);
    }
  }
  function renderGuidedSummary() {
    const summary=$('guided-summary');summary.replaceChildren();
    for(const field of guidedFields()){
      const value=guided.values[field.id];if(value===undefined||value===''||Array.isArray(value)&&!value.length)continue;
      let shown=Array.isArray(value)?value.length+' selected':typeof value==='boolean'?(value?'Yes':'No'):String(value);
      if(field.type==='select')shown=guideOptions(field).find(option=>String(option.value)===String(value))?.label||shown;
      if(shown.length>300)shown=shown.slice(0,300)+'…';
      summary.append(node('dt',field.label||field.id),node('dd',shown));
    }
    for(const slot of selectedGuidedInputs()){const input=guided.inputs[slot.id];if(input)summary.append(node('dt',slot.label||slot.id),node('dd',(input.filename||slot.id)+': '+input.rows+' rows; '+Object.values(guided.values.columns[slot.id]||{}).filter(Boolean).length+' columns mapped'));}
  }
  function renderGuidedReport(report) {
    const area=$('guided-report');area.replaceChildren();area.hidden=!report;if(!report)return;
    for(const [key,label,className] of [['errors','Resolve before generating','report-errors'],['warnings','Review these limits','report-warnings'],['summary','Setup checks','']]){
      if(!report[key]?.length)continue;const block=node('div',undefined,className);block.append(node('h4',label));const list=node('ul');
      for(const item of report[key]){
        const entry=node('li',typeof item==='string'?item:((item.field?item.field+': ':'')+(item.message||'')));
        if(key==='errors'&&item.field){const destination=guided.steps.findIndex(step=>(step.fields||[]).some(field=>field.id===item.field)||(step.id==='inputs'&&/^(inputs|columns)\./.test(item.field)));if(destination>=0){const edit=button('Edit',()=>{captureGuided();guided.step=destination;renderGuidedStep(true);});edit.classList.add('quiet');edit.setAttribute('aria-label','Edit '+item.field);entry.append(document.createTextNode(' '),edit);}}
        list.append(entry);
      }block.append(list);area.append(block);
    }
    if(report.preview){
      const preview=node('section');preview.append(node('h4',report.preview.title||'Content preview'));
      if(report.preview.text)preview.append(node('pre',report.preview.text,'log'));
      if(report.preview.facts){const details=node('details');details.append(node('summary','Structured facts'),node('pre',typeof report.preview.facts==='string'?report.preview.facts:JSON.stringify(report.preview.facts,null,2),'log'));preview.append(details);}
      area.append(preview);
    }
    if(!report.errors?.length)area.prepend(node('p','Setup checks passed. Review the summary and limits before generating.','small'));
  }
  async function startGuidedAnalysis(build,verb,allowInstall=false) {
    const own=guided;if(!own||own.projectId!==selected)throw Error('Reopen the setup for the selected project.');
    const options={module_id:own.moduleId,build_id:build.build_id};if(verb==='install')options.allow_install=allowInstall;
    const action='analysis.'+verb,result=await api('/api/actions',{project_id:own.projectId,action_id:action,options});
    $('guided-status').textContent=(verb==='run'?'Analysis and QC':verb==='install'?'Dependency installation':'Dependency check')+' started. Follow progress in Activity & outputs.';
    await refresh();
    if(guided===own){own.originToolId=null;$('guided-dialog').close();if($('tool-dialog').open)$('tool-dialog').close();}
    $('activity-panel').scrollIntoView({behavior:'smooth',block:'start'});message('Started '+(verb==='run'?'analysis and QC for the saved package.':'the analysis dependency '+(verb==='install'?'installation.':'check.')));
    return result;
  }

  function renderGuidedBuilds() {
    const area=$('guided-builds');area.replaceChildren();const project=guided.projectId;
    for(const build of (guided.builds||[]).slice(0,5)){
      const card=node('section',undefined,'guided-build');card.append(node('h4','Configured package'),node('p',(build.created_at?new Date(build.created_at).toLocaleString()+' · ':'')+(build.status||'Configuration generated'),'small'));
      const actions=node('div',undefined,'actions');
      for(const [path,label] of [[build.zip_path,'Download complete package'],[build.report_path,'Download setup report']])if(path)actions.append(button(label,event=>busy(event.currentTarget,()=>act(()=>download('/api/files?'+new URLSearchParams({project_id:project,path}),path.split('/').pop()),'guided-error')),{primary:path===build.zip_path}));
      if(build.report_path)actions.append(button('Open setup report',event=>busy(event.currentTarget,()=>act(()=>api('/api/files/open',{project_id:project,path:build.report_path}),'guided-error'))));
      if(build.engine==='r'&&/^setup-[a-f0-9]{24}$/.test(build.build_id||'')){
        const isActive=state?.jobs?.some(job=>job.project_id===project&&isRunning(job)),hasR=!!state?.runtime?.r?.available;
        const note=node('p','Run this saved version with open-source R. Generate a new package after changing settings or inputs. Results and QC are kept separately for every run.','small');card.append(note);
        const runtimeActions=node('div',undefined,'actions');runtimeActions.append(button('Check analysis dependencies',event=>busy(event.currentTarget,()=>act(()=>startGuidedAnalysis(build,'check'),'guided-error')),{disabled:isActive||!hasR}));
        runtimeActions.append(button('Run analysis and QC',event=>busy(event.currentTarget,()=>act(()=>startGuidedAnalysis(build,'run'),'guided-error')),{primary:true,disabled:isActive||!hasR}));
        if(!hasR)card.append(node('p','Install R using Computer setup, then refresh runtime status to run this package.','help'));
        if(isActive)card.append(node('p','This project already has an active task. Finish or stop it before running another.','help'));
        const install=node('details',undefined,'details-block');install.append(node('summary','Install missing analysis packages'));
        const consent=node('label',undefined,'guided-review'),check=node('input');check.type='checkbox';consent.append(check,node('span','Allow downloads from CRAN into this private project’s R library.'));
        const installButton=button('Install analysis dependencies',event=>busy(event.currentTarget,()=>act(()=>startGuidedAnalysis(build,'install',check.checked),'guided-error')),{disabled:true});check.addEventListener('change',()=>installButton.disabled=!check.checked||isActive||!hasR);install.append(consent,installButton);card.append(runtimeActions,install);
        const latest=[...(state?.jobs||[])].reverse().find(job=>job.project_id===project&&job.analysis?.build_id===build.build_id&&job.analysis?.module_id===guided.moduleId);
        if(latest){const label={running:'Running',succeeded:'Completed with automated QC',failed:'Failed — review diagnostics',stopped:'Stopped'}[latest.status]||latest.status;card.append(node('p','Latest analysis: '+label,'small'));for(const output of latest.outputs||[]){if(output.path?.endsWith('/analysis_report.html')||output.path?.endsWith('/results.zip'))actions.append(button(output.label||'Download result',event=>busy(event.currentTarget,()=>act(()=>download('/api/files?'+new URLSearchParams({project_id:project,path:output.path}),output.path.split('/').pop()),'guided-error'))));}}
      }
      card.append(actions);area.append(card);
    }
  }
  function updateGuidedGenerate() {const pending=!!guided?.pendingUploads;$('guided-preview').disabled=pending;$('guided-generate').disabled=!(guided&&!pending&&guided.validated===guidedSignature()&&!guided.report?.errors?.length&&$('guided-review-check').checked);}
  function renderGuidedStep(focus=false) {
    if(!guided)return;const steps=guidedSteps(),current=guidedCurrent();$('guided-nav').replaceChildren();
    steps.forEach((step,index)=>{const control=button((index+1)+'. '+step.title,()=>{captureGuided();guided.step=index;renderGuidedStep(true);});if(index===guided.step)control.setAttribute('aria-current','step');$('guided-nav').append(control);});
    $('guided-progress').textContent='Step '+(guided.step+1)+' of '+steps.length;$('guided-step-title').textContent=current.title;$('guided-step-description').textContent=current.description||'';
    renderGuidedFields(current.fields);renderGuidedInputs();
    const review=current.id==='review';$('guided-review-panel').hidden=!review;if(review){renderGuidedSummary();renderGuidedReport(guided.report);$('guided-review-check').checked=guided.reviewed;}
    $('guided-back').disabled=guided.step===0;$('guided-next').hidden=guided.step===steps.length-1;$('guided-next').textContent=guided.step<steps.length-1?'Next: '+steps[guided.step+1].title:'Next';
    updateGuidedGenerate();if(focus)$('guided-step-title').focus();
  }
  async function openGuided(moduleId) {
    const project=projectId(),origin=selectedTool?.id,sequence=++guidedSequence,data=await api('/api/template-setup?'+new URLSearchParams({project_id:project,module_id:moduleId}));
    if(sequence!==guidedSequence||project!==selected||stopped||!$('tool-dialog').open||selectedTool?.id!==origin)return;
    if(!data.schema?.steps?.length)throw Error('This guided setup is unavailable. Refresh the toolkit and try again.');
    const steps=[...data.schema.steps];if(!steps.some(step=>step.id==='review'))steps.push({id:'review',title:'Review & generate',description:'Check your selections and mappings, then generate a configured package.',fields:[]});
    guided={moduleId,projectId:project,originToolId:selectedTool?.id,schema:data.schema,steps,values:guidedDefaults(data.schema,data.values||{}),inputs:data.inputs||{},builds:data.builds||[],profilePath:data.profile_path,step:0,validated:'',reviewed:false,report:null};
    $('guided-title').textContent=data.schema.title||'Guided template setup';$('guided-intro').textContent=data.schema.intro||'Prepare this template for your study using forms and mapped inputs.';
    $('guided-project').textContent='Private project: '+selectedProject().name;$('guided-error').textContent='';$('guided-status').textContent='';$('guided-profile-file').value='';$('guided-profile-import').disabled=true;$('guided-profile-download').disabled=!guided.profilePath;renderGuidedStep();renderGuidedBuilds();$('tool-dialog').close();$('guided-dialog').showModal();
  }
  async function guidedAction(action) {
    captureGuided();const own=guided,sequence=guidedSequence;
    if(!own||own.projectId!==selected)throw Error('Reopen guided setup for the selected project.');
    if(['validate','generate'].includes(action)&&own.pendingUploads)throw Error('Wait for the input upload to finish, then preview the updated setup.');
    if(action==='generate'&&!(own.validated===guidedSignature()&&$('guided-review-check').checked))throw Error('Preview the current setup and review its limits before generating.');
    $('guided-status').textContent=action==='generate'?'Generating the configured package…':action==='validate'?'Checking the setup and input mappings…':'Saving your setup…';
    const data=await api('/api/template-setup',{project_id:own.projectId,module_id:own.moduleId,action,values:own.values});
    if(sequence!==guidedSequence||own!==guided)return;
    if(data.values)own.values=data.values;
    if(data.profile_path){own.profilePath=data.profile_path;$('guided-profile-download').disabled=false;}
    if(action==='save'){renderGuidedStep();$('guided-status').textContent='Setup saved in this private project.';return;}
    own.report=data.report||{errors:[],warnings:[],summary:[]};own.step=own.steps.findIndex(step=>step.id==='review');
    if(own.report.errors?.length){own.validated='';own.reviewed=false;$('guided-status').textContent='Resolve the listed setup issues, then preview again.';}
    else {own.validated=guidedSignature();$('guided-status').textContent=action==='generate'?'Configured package generated. Review its setup report before use.':'Preview complete. Review the setup summary and listed limits.';}
    if(data.build){own.builds=[data.build,...own.builds];renderGuidedBuilds();}
    renderGuidedStep(true);
  }

  async function importGuidedProfile() {
    const own=guided,sequence=guidedSequence;if(!own||own.projectId!==selected)throw Error('Reopen guided setup for the selected project.');
    const file=$('guided-profile-file').files[0];if(!file)throw Error('Choose a saved setup profile first.');
    if(file.size>1024*1024)throw Error('Choose a setup profile smaller than 1 MB.');
    let profile;try{profile=JSON.parse(await file.text());}catch{throw Error('Choose a valid JSON setup profile.');}
    if(sequence!==guidedSequence||own!==guided)return;
    const data=await api('/api/template-profile',{project_id:own.projectId,module_id:own.moduleId,profile});
    if(sequence!==guidedSequence||own!==guided)return;
    own.values=guidedDefaults(own.schema,data.values||{});own.profilePath=data.profile_path||own.profilePath;own.report=null;own.step=0;guidedChanged();renderGuidedStep(true);
    $('guided-profile-file').value='';$('guided-profile-import').disabled=true;$('guided-profile-download').disabled=!own.profilePath;
    $('guided-status').textContent='Imported setup choices. Add or review this project’s CSV inputs and mappings, then preview again.';
  }

  function openTool(id) {
    const module=modules().find(module=>module.id===id);if(!module)return;selectedTool=module;selectedAction=null;
    $('tool-title').textContent=module.title;$('tool-summary').textContent=module.summary;$('tool-error').textContent='';$('run-error').textContent='';$('configure-error').textContent='';toolNotice('');$('tool-details').replaceChildren();$('tool-actions').replaceChildren();$('run-form').hidden=true;$('configure-form').hidden=true;
    addDetail('What you can adapt',module.customization);addDetail('Saving your work',module.persistence);addDetail('Scope and limits',module.limits);addDetail('Outputs',module.outputs,{list:true});
    const docs=node('div');docs.append(node('h3','Guides & reference'));const list=node('ul');
    for(const doc of module.docs||[]){const url=documentURL(doc.path);if(url){const li=node('li');li.append(link(doc.label||doc.path,url));list.append(li);}}
    const demo=safeURL(module.demo_url);if(demo){const li=node('li');li.append(link((module.browser_label||'Open browser demo')+' ↗',demo));list.append(li);}docs.append(list);if(list.childElementCount)$('tool-details').append(docs);
    renderToolProject(module);
    for(const raw of module.actions||[]){const action=actionDetails(raw);
      if(action.type==='open'){const path=action.path;if(/^https?:/.test(path||'')){const url=safeURL(path);if(url)$('tool-actions').append(link(action.label+' ↗',url,'btn'));}else if(state&&path)$('tool-actions').append(button(action.label,event=>busy(event.currentTarget,()=>act(()=>fileAction(path),'tool-error')),{disabled:!selectedProject()}));}
      else if(!state)continue;
      else if(action.type==='guided'){$('tool-actions').append(button(action.label,event=>busy(event.currentTarget,()=>act(()=>openGuided(action.module_id||action.id),'tool-error')),{primary:true,disabled:!selectedProject()}));}
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
  $('guided-profile-file').addEventListener('change',()=>{$('guided-profile-import').disabled=!$('guided-profile-file').files.length;});
  $('guided-profile-import').addEventListener('click',()=>busy($('guided-dialog'),()=>act(importGuidedProfile,'guided-error')).finally(()=>{if(guided){$('guided-profile-import').disabled=!$('guided-profile-file').files.length;$('guided-profile-download').disabled=!guided.profilePath;updateGuidedGenerate();}}));
  $('guided-profile-download').addEventListener('click',event=>busy(event.currentTarget,()=>act(()=>download('/api/files?'+new URLSearchParams({project_id:guided.projectId,path:guided.profilePath}),guided.moduleId+'-setup.json'),'guided-error')));
  $('guided-form').addEventListener('submit',event=>event.preventDefault());
  $('guided-back').addEventListener('click',()=>{captureGuided();guided.step=Math.max(0,guided.step-1);renderGuidedStep(true);});
  $('guided-next').addEventListener('click',()=>{captureGuided();const invalid=Array.from($('guided-fields').querySelectorAll('input,select,textarea')).find(input=>!input.checkValidity());if(invalid){invalid.reportValidity();return;}guided.step=Math.min(guided.steps.length-1,guided.step+1);renderGuidedStep(true);});
  $('guided-review-check').addEventListener('change',()=>{if(guided)guided.reviewed=$('guided-review-check').checked;updateGuidedGenerate();});
  for(const [id,action] of [['guided-save','save'],['guided-preview','validate'],['guided-generate','generate']])$(id).addEventListener('click',()=>busy($('guided-dialog'),()=>act(()=>guidedAction(action),'guided-error')).finally(()=>{updateGuidedGenerate();if(guided)$('guided-profile-download').disabled=!guided.profilePath;}));
  $('guided-dialog').addEventListener('close',()=>{const origin=guided?.originToolId;guidedSequence++;guided=null;if(!stopped&&state&&origin)openTool(origin);});
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
