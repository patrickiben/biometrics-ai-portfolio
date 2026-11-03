// Python runs in a separate browser worker. Only reviewed providers are callable.
import {loadPyodide} from '../../browser-runtime/pyodide/pyodide.mjs';
let py, ready, examplesReady, validationReady, sourceManifest, queue=Promise.resolve(), counter=0;
const rPending=new Map();
self.runRCommand=payload=>new Promise((resolve,reject)=>{const id=++counter;rPending.set(id,{resolve,reject});self.postMessage({kind:'r-command',id,payload:JSON.parse(payload)});});
self.validationProgress=message=>self.postMessage({kind:'progress',message:String(message)});
async function initialize(){
 self.postMessage({kind:'progress',message:'Loading browser Python and reviewed setup sources…'});
 py=await loadPyodide({indexURL:new URL('../../browser-runtime/pyodide/',import.meta.url).href});
 const manifest=sourceManifest=await (await fetch(new URL('../../browser-runtime/sources.json',import.meta.url))).json();
 const bytes=new Uint8Array(await (await fetch(new URL('../../browser-runtime/guided-sources.zip',import.meta.url))).arrayBuffer());
 const hash=[...new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))].map(x=>x.toString(16).padStart(2,'0')).join('');
 if(hash!==manifest.guided.sha256)throw Error('Browser setup source integrity check failed. Reload the published workspace.');
 py.FS.mkdirTree('/repo');py.FS.writeFile('/sources.zip',bytes);
 await py.runPythonAsync("import zipfile,sys\nwith zipfile.ZipFile('/sources.zip') as z: z.extractall('/repo')\nsys.path.insert(0,'/repo')\nfrom browser_modules.workbench import backend\nbackend.reset()");
 return py;
}
async function initializeValidation(){
 self.validationProgress('Loading the complete reviewed toolkit snapshot for the original validation gates…');
 const meta=sourceManifest.validation;
 if(!meta||!meta.sha256||!meta.files)throw Error('The reviewed validation source manifest is missing.');
 const response=await fetch(new URL('../../browser-runtime/validation-sources.zip',import.meta.url));
 if(!response.ok)throw Error('Could not load the reviewed validation sources.');
 const bytes=new Uint8Array(await response.arrayBuffer());
 const hash=[...new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))].map(x=>x.toString(16).padStart(2,'0')).join('');
 if(hash!==meta.sha256)throw Error('Browser validation source integrity check failed. Reload the published workspace.');
 py.FS.writeFile('/validation-sources.zip',bytes);py.globals.set('_validation_inventory',JSON.stringify(meta.files));
 await py.runPythonAsync(`
import base64,hashlib,json,pathlib,sys,zipfile
_validation_root = pathlib.Path('/validation-project')
_validation_inventory_dict = json.loads(_validation_inventory)
with zipfile.ZipFile('/validation-sources.zip') as _archive:
    _names = _archive.namelist()
    if len(_names) != len(set(_names)) or set(_names) != set(_validation_inventory_dict):
        raise ValueError('The validation archive differs from its reviewed inventory.')
    for _name in _names:
        _path = pathlib.PurePosixPath(_name)
        if _path.is_absolute() or any(_part in ('', '.', '..') for _part in _name.split('/')) or '\\\\' in _name or ':' in _name:
            raise ValueError('Unsafe path in the reviewed validation archive.')
        _bytes = _archive.read(_name)
        if hashlib.sha256(_bytes).hexdigest() != _validation_inventory_dict[_name]:
            raise ValueError('A validation source failed its integrity check: ' + _name)
        _target = _validation_root / _name
        _target.parent.mkdir(parents=True,exist_ok=True)
        _target.write_bytes(_bytes)
sys.path.insert(0,str(_validation_root))
from browser_modules.validation import browser_session
from js import runRCommand,validationProgress
async def _validation_r_bridge(request):
    return json.loads(str(await runRCommand(json.dumps(request))))
browser_session.initialize(_validation_root,_validation_inventory_dict,_validation_r_bridge,lambda line: validationProgress(line))
pathlib.Path('/validation-sources.zip').unlink()
`);
 self.validationProgress('Reviewed validation sources verified. Manual and unsigned gates retain those states.');
}
self.onmessage=event=>{
 const m=event.data;
 if(m.kind==='r-response'){const pending=rPending.get(m.id);if(!pending)return;rPending.delete(m.id);m.error?pending.reject(Error(m.error)):pending.resolve(JSON.stringify(m.result));return;}
 queue=queue.then(async()=>{
  try{await(ready??=initialize());
   if(m.operation==='example')await(examplesReady??=(async()=>{const meta=sourceManifest.examples;if(!meta)throw Error('Synthetic example manifest missing.');const bytes=new Uint8Array(await(await fetch(new URL('../../'+meta.url,import.meta.url))).arrayBuffer());const hash=[...new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))].map(x=>x.toString(16).padStart(2,'0')).join('');if(hash!==meta.sha256)throw Error('Synthetic example integrity mismatch.');py.FS.writeFile('/repo/browser_modules/workbench/example-inputs.json',bytes);})());
   const validation=typeof m.operation==='string'&&m.operation.startsWith('validation-');
   if(validation)await(validationReady??=initializeValidation());
   py.globals.set('_browser_request',JSON.stringify(m.payload||{}));py.globals.set('_browser_operation',m.operation);
   const result=await py.runPythonAsync(validation?
    "import json\njson.dumps(await browser_session.call(_browser_operation,json.loads(_browser_request)),ensure_ascii=False)":
    "import json,traceback\ntry:\n    _answer=backend.call(_browser_operation,json.loads(_browser_request))\nexcept Exception as _error:\n    _answer={'_browser_error':str(_error),'_diagnostic':traceback.format_exc()}\njson.dumps(_answer,ensure_ascii=False)");
   const value=JSON.parse(result);if(value?._browser_error)self.postMessage({kind:'result',id:m.id,error:value._browser_error,diagnostics:value._diagnostic});else self.postMessage({kind:'result',id:m.id,result:value});
  }catch(error){self.postMessage({kind:'result',id:m.id,error:String(error.message||error)});}
 });
};
