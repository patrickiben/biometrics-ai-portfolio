// Client-neutral planning records. No network, storage, signatures or approval logic.
export const fields=['id','stage','deliverable','type','description','owner','inputs','outputs','standard','qc','deliverable_note','standard_note','status','due_date','notes'];
// Columns from earlier starters. On import a non-empty value moves into notes, labeled, so nothing is lost silently.
export const legacy={ai_tier:'AI assistance category',ai_engine:'AI tool or engine plan',ai_use:'AI assistance notes'};
export const labels={id:'Record ID',stage:'Study stage',deliverable:'Deliverable',type:'Deliverable type',description:'Description',owner:'Responsible role or person',inputs:'Required inputs',outputs:'Expected outputs',standard:'Standards and references',qc:'Planned QC and review',deliverable_note:'Deliverable reference note',standard_note:'Standards reference note',status:'Planning status',due_date:'Target date',notes:'Study-specific notes'};
export const statuses=['Not started','In progress','Ready for review','Review recorded','Not applicable'];
export const maxBytes=20*1024*1024,maxRows=2000;
const text=(x,label)=>{if(typeof x!=='string')throw Error(label+' must be text.');if(x.length>100000||x.includes('\0'))throw Error(label+' is too long or contains a null character.');return x;};
export function normalize(input){
 let study='',rows=input;
 if(!Array.isArray(input)){
  if(!input||typeof input!=='object'||input.schema!==1||input.kind!=='toolkit-pipeline-register')throw Error('Expected a toolkit register JSON document or an array of register rows.');
  const allowed=new Set(['schema','kind','study','rows','exported_at','notice','source']);
  if(Object.keys(input).some(x=>!allowed.has(x)))throw Error('Unknown register metadata. Keep additional content in row notes.');
  study=text(input.study??'','Study label');rows=input.rows;
 }
 if(!Array.isArray(rows)||rows.length>maxRows)throw Error('A register must contain at most '+maxRows+' rows.');
 const seen=new Set();
 const clean=rows.map((row,i)=>{
  if(!row||typeof row!=='object'||Array.isArray(row))throw Error('Row '+(i+1)+' must be a record.');
  if(Object.keys(row).some(x=>!fields.includes(x)&&!(x in legacy)))throw Error('Unknown column in row '+(i+1)+'. Use the provided register columns.');
  const result=Object.fromEntries(fields.map(k=>[k,text(row[k]??'',labels[k]) ]));
  const moved=Object.keys(legacy).filter(k=>row[k]!=null&&text(row[k],legacy[k]).trim()).map(k=>'['+legacy[k]+', earlier column] '+row[k]);
  if(moved.length)result.notes=[result.notes,...moved].filter(Boolean).join('\n');
  if(!result.id.trim()||!result.deliverable.trim())throw Error('Each row needs a record ID and deliverable.');
  if(seen.has(result.id.trim()))throw Error('Duplicate record ID: '+result.id.trim());
  seen.add(result.id.trim());result.id=result.id.trim();
  result.status=result.status||'Not started';
  if(!statuses.includes(result.status))throw Error('Unknown planning status in '+result.id+'.');
  if(result.due_date){
   if(!/^\d{4}-\d{2}-\d{2}$/.test(result.due_date))throw Error('Target dates must use YYYY-MM-DD.');
   const parsed=new Date(result.due_date+'T00:00:00Z');
   if(!Number.isFinite(parsed.getTime())||parsed.toISOString().slice(0,10)!==result.due_date)throw Error('Invalid target date in '+result.id+'.');
  }
  return result;
 });
 return {study,rows:clean};
}
export function documentFor(state){return {schema:1,kind:'toolkit-pipeline-register',study:state.study,rows:normalize({schema:1,kind:'toolkit-pipeline-register',...state}).rows,exported_at:new Date().toISOString(),notice:'Planning records only. Status and QC text are user-entered; this export is not a scientific approval, electronic signature or audit trail.'};}
export function safeCell(value){const s=String(value);return /^[\s]*[=+\-@]/.test(s)||/^[\t\r\n]/.test(s)?"'"+s:s;}
const csvCell=s=>'"'+safeCell(s).replaceAll('"','""')+'"';
export function csvFor(state){const clean=normalize({schema:1,kind:'toolkit-pipeline-register',...state});return '\uFEFF'+[['study_label',...fields].map(csvCell).join(','),...clean.rows.map(r=>[clean.study,...fields.map(k=>r[k])].map(csvCell).join(','))].join('\r\n')+'\r\n';}
export function parseCSV(input){
 let source=input.replace(/^\uFEFF/,''),rows=[],row=[],cell='',quoted=false,closed=false;
 for(let i=0;i<source.length;i++){
  const c=source[i];
  if(quoted){if(c==='"'){if(source[i+1]==='"'){cell+='"';i++;}else{quoted=false;closed=true;}}else cell+=c;continue;}
  if(c==='"'){if(cell||closed)throw Error('Unexpected quote in CSV.');quoted=true;continue;}
  if(c===','||c==='\n'||c==='\r'){
   row.push(cell);cell='';closed=false;
   if(c!==','){if(c==='\r'&&source[i+1]==='\n')i++;rows.push(row);row=[];}
   continue;
  }
  if(closed)throw Error('Unexpected text after a quoted CSV value.');
  cell+=c;
 }
 if(quoted)throw Error('Unclosed quoted CSV value.');
 if(cell||closed||row.length){row.push(cell);rows.push(row);}
 if(!rows.length)throw Error('The CSV file is empty.');
 const header=rows.shift();
 if(header.length!==new Set(header).size||header.some(k=>k!=='study_label'&&!fields.includes(k)&&!(k in legacy)))throw Error('CSV contains duplicate or unknown columns.');
 if(!header.includes('id')||!header.includes('deliverable'))throw Error('CSV needs id and deliverable columns.');
 let study='';const studyValues=new Set();
 const records=rows.map((r,i)=>{
  if(r.length!==header.length)throw Error('CSV row '+(i+2)+' has the wrong number of columns.');
  const result={};header.forEach((k,j)=>{if(k==='study_label')studyValues.add(r[j]);else result[k]=r[j];});return result;
 });
 if(studyValues.size>1)throw Error('All rows must use the same study_label.');
 study=[...studyValues][0]||'';
 return normalize({schema:1,kind:'toolkit-pipeline-register',study,rows:records});
}
export function parseFile(text,name){if(new TextEncoder().encode(text).length>maxBytes)throw Error('The import exceeds 20 MiB.');return name.toLowerCase().endsWith('.csv')?parseCSV(text):normalize(JSON.parse(text));}
