import {fields,labels,statuses,maxBytes,normalize,documentFor,csvFor,parseFile} from './core.mjs';
const $=id=>document.getElementById(id);let state={study:'',rows:[]},selected=null,dirty=false,history=[],loaded=false;
const node=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;};
function notice(message){$('status').textContent=message;$('error').hidden=true;}
function error(e){$('error').textContent=e.message||String(e);$('error').hidden=false;}
function remember(){history.push(structuredClone(state));if(history.length>20)history.shift();$('undo').disabled=false;}
function noDraft(){if(dirty)throw Error('Save or discard row edits before continuing.');}
function run(fn){return async event=>{try{await fn(event);}catch(e){error(e);}};}
function filters(){
 const current=$('stage').value;const stages=[...new Set(state.rows.map(r=>r.stage).filter(Boolean))].sort();$('stage').replaceChildren(new Option('All stages',''),...stages.map(s=>new Option(s,s)));$('stage').value=stages.includes(current)?current:'';
}
function render(){
 $('study').value=state.study;filters();const query=$('search').value.toLowerCase(),stage=$('stage').value,status=$('status-filter').value;
 const visible=state.rows.filter(r=>(!stage||r.stage===stage)&&(!status||r.status===status)&&(!query||fields.some(k=>r[k].toLowerCase().includes(query))));
 $('count').textContent=visible.length+' of '+state.rows.length+' rows';$('records').replaceChildren();
 for(const row of visible){const b=node('button',undefined,'record');b.type='button';b.dataset.id=row.id;b.setAttribute('aria-pressed',String(selected===row.id));b.setAttribute('aria-label','Edit '+row.id+': '+row.deliverable);b.append(node('span',row.id+' · '+(row.stage||'No stage'),'record-meta'),node('strong',row.deliverable),node('span',row.status+' · '+(row.owner||'Owner not assigned'),'small'));b.onclick=run(()=>{noDraft();edit(row);render();if(innerWidth<=800)$('edit-title').scrollIntoView({behavior:'smooth'});});$('records').append(b);}
 if(!visible.length)$('records').append(node('p',state.rows.length?'No records match these filters.':'Your register is blank. Add a deliverable or load the starter.','small'));
 $('undo').disabled=!history.length;
}
function edit(row=null){
 selected=row?.id??null;dirty=false;$('draft').textContent='No unsaved row edits.';$('editor').hidden=!row;$('empty-editor').hidden=!!row;$('fields').replaceChildren();
 if(!row)return;
 for(const key of fields){
  const label=node('label',labels[key]);label.htmlFor='row-'+key;
  const control=key==='status'?document.createElement('select'):document.createElement(['id','stage','deliverable','type','owner','due_date'].includes(key)?'input':'textarea');
  control.id='row-'+key;control.name=key;
  if(key==='status')control.append(...statuses.map(s=>new Option(s,s)));
  if(key==='due_date')control.type='date';
  if(key==='id'||key==='deliverable')control.required=true;
  control.value=row[key]||'';control.maxLength=100000;
  control.addEventListener('input',()=>{dirty=true;$('draft').textContent='Unsaved row edits. Save this deliverable to include them in exports.';});label.append(control);$('fields').append(label);
 }
 $('delete').disabled=!state.rows.some(r=>r.id===selected);
}
function replace(next,message){remember();state=next;edit();$('search').value='';$('status-filter').value='';$('stage').value='';render();notice(message);}
function download(content,type,name){const url=URL.createObjectURL(new Blob([content],{type})),a=node('a');a.href=url;a.download=name;document.body.append(a);a.click();setTimeout(()=>{a.remove();URL.revokeObjectURL(url);},1000);}
function printContent(){
 $('printout').replaceChildren(node('h1','Study deliverable register'),node('p',state.study||'No study label'),node('p','Complete register: '+state.rows.length+' records. Planning notes only; no scientific approval, electronic signature or audit trail is provided.'));
 if(dirty)$('printout').append(node('p','Unsaved row edits are not included. This print view contains the last saved records in this session.'));
 for(const row of state.rows){const article=node('article');article.append(node('h2',row.id+' · '+row.deliverable));const dl=node('dl');for(const key of fields){dl.append(node('dt',labels[key]),node('dd',row[key]||'—'));}article.append(dl);$('printout').append(article);}
}
$('status-filter').append(...statuses.map(s=>new Option(s,s)));
for(const id of ['search','stage','status-filter'])$(id).addEventListener('input',render);
$('study').addEventListener('input',()=>{state.study=$('study').value;loaded=true;});
$('starter').onclick=run(async()=>{noDraft();$('starter').disabled=true;try{const response=await fetch('../../biostat_pipeline/_register.json',{credentials:'omit',referrerPolicy:'no-referrer'});if(!response.ok)throw Error('The reference starter could not be loaded.');const next=normalize(await response.json());replace(next,'Loaded all '+next.rows.length+' reference records. Review and adapt them for your study.');loaded=true;}finally{$('starter').disabled=false;}});
$('new').onclick=run(()=>{noDraft();if(state.rows.length>=2000)throw Error('This browser register supports up to 2,000 rows.');let n=1;while(state.rows.some(r=>r.id==='ROW-'+String(n).padStart(3,'0')))n++;edit(Object.fromEntries(fields.map(k=>[k,k==='id'?'ROW-'+String(n).padStart(3,'0'):k==='status'?'Not started':''])));dirty=true;$('draft').textContent='New record. Complete its deliverable name and save.';$('row-deliverable').focus();});
$('editor').onsubmit=run(event=>{event.preventDefault();const row=Object.fromEntries(new FormData($('editor')));const next=structuredClone(state);const at=next.rows.findIndex(r=>r.id===selected);if(at<0)next.rows.push(row);else next.rows[at]=row;const checked=normalize({schema:1,kind:'toolkit-pipeline-register',...next});remember();state=checked;edit(state.rows.find(r=>r.id===row.id.trim()));render();loaded=true;notice('Saved '+row.id.trim()+' in this tab. Export JSON to keep your work.');});
$('discard').onclick=()=>{edit(state.rows.find(r=>r.id===selected));render();notice('Discarded unsaved row edits.');};
$('delete').onclick=run(()=>{noDraft();if(!selected)return;const id=selected;remember();state.rows=state.rows.filter(r=>r.id!==id);edit();render();notice('Removed '+id+'. Undo is available.');});
$('undo').onclick=run(()=>{noDraft();if(!history.length)return;state=history.pop();edit();render();notice('Restored the previous register.');});
$('reset').onclick=run(()=>{noDraft();replace({study:'',rows:[]},'Reset to a blank register. Undo restores the previous records.');});
$('import').onchange=run(async event=>{const file=event.target.files[0];if(!file)return;try{noDraft();if(file.size>maxBytes)throw Error('The import exceeds 20 MiB.');const next=parseFile(await file.text(),file.name);replace(next,'Imported '+next.rows.length+' records. No content was sent to a server.');loaded=true;}finally{event.target.value='';}});
$('json').onclick=run(()=>{noDraft();download(JSON.stringify(documentFor(state),null,2)+'\n','application/json','study-deliverable-register.json');notice('Exported every row and field as JSON.');});
$('csv').onclick=run(()=>{noDraft();download(csvFor(state),'text/csv;charset=utf-8','study-deliverable-register.csv');notice('Exported every row and field as spreadsheet-safe CSV.');});
$('print').onclick=run(()=>{noDraft();printContent();window.print();});
window.addEventListener('beforeprint',printContent);
window.addEventListener('beforeunload',event=>{if(dirty||loaded&&(state.rows.length||state.study)){event.preventDefault();event.returnValue='';}});
render();
