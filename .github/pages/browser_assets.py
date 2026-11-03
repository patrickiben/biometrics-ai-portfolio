"""Package reviewed source and pinned Python assets for browser-only execution."""
from pathlib import Path
import importlib.util
import gzip, hashlib, io, json, os, re, shutil, subprocess, sys, tarfile, urllib.request, zipfile
ROOT = Path(__file__).resolve().parents[2]
PYODIDE_VERSION = '314.0.7'
PYODIDE_FILES = ['pyodide.mjs', 'pyodide.asm.mjs', 'pyodide.asm.wasm', 'python_stdlib.zip', 'pyodide-lock.json']
PRIVATE = re.compile(r'(^|/)[^/]*\.env($|\.)|\.(sqlite3?|db)(-(wal|shm|journal))?$|\.eml$|(^|/)(config\.json|\.open-study-tracker|\.desktop-state\.json|\.desktop\.lock|launcher\.log|project\.json|launcher-settings\.json|\.launcher-session\.json|\.toolkit\.lock|\.biostat-toolkit|toolkit_configuration|input-backups|template_inputs|template_outputs|template_runs|mail-preview)(/|$)', re.I)
GUIDED = ['toolkit_launcher/guided_tlf.py','toolkit_launcher/guided_modules.py','toolkit_launcher/analysis_contracts.py','toolkit_launcher/analysis_form_fields.py','toolkit_launcher/analysis_runner.R','toolkit_launcher/analysis_monitor.R','browser_modules/workbench/backend.py','assets/theme/tokens.css']
GUIDED_DIRS = ['r_tlf_pseudocode/','sas_tlf_pseudocode/','sas_r_automation/macro_library/','slm_wiki/macro_library/','tlf_interpret/R/']

def digest(data): return hashlib.sha256(data).hexdigest()

def reviewed_files():
    names = subprocess.check_output(['git','-c','core.quotepath=off','ls-files','--cached','--others','--exclude-standard'],cwd=ROOT,text=True).splitlines()
    result=[]
    for name in sorted(set(names)):
        p=ROOT/name
        if not p.is_file() or name.startswith(('.git/','_site/','node_modules/')) or '/node_modules/' in name: continue
        if PRIVATE.search(name) and not name.endswith('.env.example'): continue
        if any(parent.is_symlink() for parent in [p,*p.parents] if parent!=ROOT.parent): raise ValueError('Linked public source: '+name)
        if not p.resolve().is_relative_to(ROOT): raise ValueError('Outside-checkout public source: '+name)
        result.append(name)
    return result

def archive(destination,names):
    inventory={}
    with zipfile.ZipFile(destination,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for name in names:
            data=(ROOT/name).read_bytes();inventory[name]=digest(data)
            info=zipfile.ZipInfo(name,(2026,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=0o100644<<16
            z.writestr(info,data)
    return {'sha256':digest(destination.read_bytes()),'bytes':destination.stat().st_size,'files':inventory}

def python_assets(out):
    target=out/'pyodide';target.mkdir(parents=True,exist_ok=True)
    cache=Path(os.environ.get('TOOLKIT_BROWSER_ASSET_CACHE',str(Path.home()/'.cache'/'trial-biostat-browser')))/('pyodide-'+PYODIDE_VERSION);cache.mkdir(parents=True,exist_ok=True)
    locked_path=ROOT/'browser_modules/workbench/python-assets.lock.json'
    locked=json.loads(locked_path.read_text()) if locked_path.exists() else None
    metadata={}
    for name in PYODIDE_FILES:
        url=f'https://cdn.jsdelivr.net/pyodide/v{PYODIDE_VERSION}/full/{name}'
        source=cache/name
        if not source.is_file():
            with urllib.request.urlopen(url,timeout=120) as response: data=response.read()
            source.write_bytes(data)
        data=source.read_bytes(); item={'url':url,'sha256':digest(data),'bytes':len(data)}
        if locked and item!=locked['files'].get(name): raise ValueError('Pinned Python runtime integrity mismatch: '+name)
        shutil.copy2(source,target/name);metadata[name]=item
    if not locked: raise ValueError('Python runtime lock required. Use --lock-python once after reviewing upstream assets.')
    return {'version':PYODIDE_VERSION,'files':metadata}

def model_assets(out):
    version='0.2.87';url=f'https://registry.npmjs.org/@mlc-ai/web-llm/-/web-llm-{version}.tgz'
    expected='68b81b32f0c04f8b564820b65e00fda9191ffd5a649ac4addd47c3311f02de7f'
    cache=Path.home()/'.cache/trial-biostat-browser'/('webllm-'+version);cache.mkdir(parents=True,exist_ok=True)
    archive_path=cache/'package.tgz'
    if not archive_path.exists():
        with urllib.request.urlopen(url,timeout=120) as response: archive_path.write_bytes(response.read())
    data=archive_path.read_bytes()
    if digest(data)!=expected: raise ValueError('Pinned WebLLM runtime integrity mismatch.')
    target=out/'webllm';target.mkdir(parents=True,exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(data)) as package:
        for source,name in [('package/lib/index.js','index.js'),('package/LICENSE','LICENSE')]:
            (target/name).write_bytes(package.extractfile(source).read())
    return {'version':version,'url':url,'sha256':expected,'license':'Apache-2.0','model':'Qwen2.5-0.5B-Instruct-q4f32_1-MLC','model_load':'explicit user action; external public model assets'}


def lock_python():
    cache=Path.home()/'.cache/trial-biostat-browser'/('pyodide-'+PYODIDE_VERSION);cache.mkdir(parents=True,exist_ok=True)
    files={}
    for name in PYODIDE_FILES:
        url=f'https://cdn.jsdelivr.net/pyodide/v{PYODIDE_VERSION}/full/{name}'
        with urllib.request.urlopen(url,timeout=120) as response: data=response.read()
        (cache/name).write_bytes(data);files[name]={'url':url,'sha256':digest(data),'bytes':len(data)}
    (ROOT/'browser_modules/workbench/python-assets.lock.json').write_text(json.dumps({'version':PYODIDE_VERSION,'upstream':'https://pyodide.org/en/stable/usage/webworker.html','files':files},indent=2)+'\n')

def package_index(site):
    result={}
    for path in sorted((site/'shinylive/webr/packages').glob('*/*.tgz')):
        with tarfile.open(path) as archive_file:
            description=next((m for m in archive_file.getmembers() if m.name.count('/')==1 and m.name.endswith('/DESCRIPTION')),None)
            if not description: continue
            text=archive_file.extractfile(description).read().decode('utf-8')
        text=re.sub(r'\n[ \t]+',' ',text)
        meta=dict(re.findall(r'^([^:\n]+):\s*(.*)$',text,re.M))
        deps=[]
        for key in ['Depends','Imports','LinkingTo']:
            deps += [re.sub(r'\s*\(.*','',x).strip() for x in meta.get(key,'').split(',') if x.strip()]
        result[meta['Package']]={'url':path.relative_to(site).as_posix(),'sha256':digest(path.read_bytes()),'bytes':path.stat().st_size,'version':meta['Version'],'dependencies':sorted(set(deps)-{'R'})}
    return result

def build(site):
    locked=json.loads((ROOT/'browser_modules/workbench/r-assets.lock.json').read_text())
    for name,expected in locked['files'].items():
        data=(site/name).read_bytes()
        if digest(data)!=expected['sha256'] or len(data)!=expected['bytes']: raise ValueError('Pinned R runtime integrity mismatch: '+name)
    # Never publish a developer backup accidentally present in an external asset cache.
    for backup in (site/'shinylive').rglob('*.bak'): backup.unlink()
    out=site/'browser-runtime';out.mkdir(parents=True,exist_ok=True)
    names=reviewed_files()
    spec=importlib.util.spec_from_file_location('browser_validation',ROOT/'browser_modules/validation/browser_validation.py')
    validation=importlib.util.module_from_spec(spec);spec.loader.exec_module(validation)
    required=validation.source_requirements()
    missing=set(required['essential_paths'])-set(names)
    if missing: raise ValueError('Missing browser validation sources: '+str(sorted(missing)))
    for directory in required['required_directories']:
        if not any(name.startswith(directory+'/') for name in names): raise ValueError('Incomplete browser validation inventory: '+directory)
    validation.validate_source_manifest(ROOT,names)
    selected=[p for p in names if p in GUIDED or any(p.startswith(prefix) for prefix in GUIDED_DIRS)]
    missing=set(GUIDED)-set(selected)
    if missing: raise ValueError('Missing guided browser sources: '+str(missing))
    example_path=out/'example-inputs.json'
    subprocess.run(['Rscript','browser_modules/workbench/example_inputs.R',str(example_path)],cwd=ROOT,check=True)
    metadata={'schema':1,'guided':archive(out/'guided-sources.zip',selected),'validation':archive(out/'validation-sources.zip',names)}
    metadata['examples']={'url':'browser-runtime/example-inputs.json','sha256':digest(example_path.read_bytes()),'bytes':example_path.stat().st_size}
    compat_spec=importlib.util.spec_from_file_location('cubature_compat',ROOT/'browser_modules/compat/cubature/rebuild.py')
    compat=importlib.util.module_from_spec(compat_spec);compat_spec.loader.exec_module(compat)
    metadata['r_compatibility']=compat.install_into(site)
    metadata['python']=python_assets(out)
    metadata['model_runtime']=model_assets(out)
    (out/'sources.json').write_text(json.dumps(metadata,indent=2)+'\n')
    (out/'packages.json').write_text(json.dumps(package_index(site),indent=2)+'\n')
    print('Browser sources:',len(selected),'guided files;',len(names),'QC reference files;',round(sum(x.stat().st_size for x in out.rglob('*') if x.is_file())/1e6,1),'MB')

if __name__=='__main__':
    if sys.argv[1:] == ['--lock-python']: lock_python()
    else: build(Path(sys.argv[1]).resolve())
