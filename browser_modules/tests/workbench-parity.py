"""Compare actual browser exports with native execution of the same generated sources."""
import csv,json,math,subprocess,sys,zipfile
from pathlib import Path
source=Path(sys.argv[1]).resolve();destination=source/'native-parity';destination.mkdir(exist_ok=True)
report=[]
archives=sorted(source.glob('*.zip'))
for archive in archives:
    target=destination/archive.stem;target.mkdir(exist_ok=True)
    with zipfile.ZipFile(archive) as z:
        if z.testzip(): raise ValueError('ZIP checksum failed: '+archive.name)
        for name in z.namelist():
            if Path(name).is_absolute() or '..' in Path(name).parts or '\\' in name: raise ValueError('Unsafe archive path')
        z.extractall(target/'browser')
    build=target/'browser/configuration'
    if not build.is_dir(): continue  # The manual worklist has no R execution claim.
    profile=json.loads((build/'setup_profile.json').read_text());module=profile['module_id']
    if module=='localmind': continue
    output=target/'native';output.mkdir(exist_ok=True)
    plan={'schema':1,'module_id':module,'build_root':str(build),'run_root':str(output),'source_root':str(build),'build_id':'native-qc','run_id':'native-qc','approved':False,'execution_mode':'native R parity QC'}
    plan_path=target/'plan.json';plan_path.write_text(json.dumps(plan));script=target/'run.R'
    script.write_text('source('+json.dumps(str(build/'toolkit_launcher/analysis_runner.R'))+'); stopifnot(run_analysis('+json.dumps(str(plan_path))+'))')
    with (target/'native.log').open('w') as log: subprocess.run(['Rscript',str(script)],stdout=log,stderr=subprocess.STDOUT,check=True)
    count=cells=0;maximum=0.;errors=[]
    for actual in (target/'browser/outputs').rglob('component-*.csv'):
        relative=actual.relative_to(target/'browser');expected=output/relative
        if not expected.exists(): errors.append(str(relative)+': missing native result');continue
        a=list(csv.reader(actual.open()));b=list(csv.reader(expected.open()))
        if len(a)!=len(b): errors.append(str(relative)+': row count differs');continue
        for row,(av,bv) in enumerate(zip(a,b)):
            if len(av)!=len(bv):errors.append(str(relative)+': column count differs');continue
            for col,(x,y) in enumerate(zip(av,bv)):
                cells+=1
                if x==y:continue
                try:
                    xx,yy=float(x),float(y)
                    if math.isnan(xx) and math.isnan(yy):continue
                    delta=abs(xx-yy)/max(1,abs(xx),abs(yy));maximum=max(maximum,delta)
                    if not math.isclose(xx,yy,rel_tol=1e-7,abs_tol=1e-8):errors.append(f'{relative} [{row},{col}]: {x} != {y}')
                except ValueError: errors.append(f'{relative} [{row},{col}]: {x} != {y}')
        count+=1
    if count==0:errors.append('No numerical CSV components compared')
    report.append({'case':archive.stem,'csv_components':count,'cells':cells,'maximum_relative_difference':maximum,'errors':errors})
    print(json.dumps(report[-1]),flush=True)
(destination/'report.json').write_text(json.dumps(report,indent=2)+'\n')
if len(report)<9 or any(x['errors'] for x in report):raise SystemExit('Browser/native numerical parity failed or required runs are missing')
