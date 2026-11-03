"""Browser adapter for canonical guided providers. No network or subprocesses."""
import base64
import csv
import hashlib
import io
import json
import shutil
from pathlib import Path
from toolkit_launcher import guided_modules, guided_tlf

ROOT = Path('/repo')
SESSION = Path('/session')
MODULES = {'r_tlf', 'sas_tlf', 'sas_monitor', 'interpretation', 'localmind'}
MAX_BYTES = 16 * 1024 * 1024
MAX_ROWS = 100000


def provider(module):
    if module not in MODULES:
        raise ValueError('Choose a supported browser module.')
    return guided_tlf if module in {'r_tlf', 'sas_tlf'} else guided_modules


def schema(module):
    return provider(module).schema(module, ROOT)


def check_profile(module, values):
    if not isinstance(values, dict): raise ValueError('Settings must be an object.')
    fields = {f['id']: f for step in schema(module)['steps'] for f in step.get('fields', [])}
    if set(values) - (set(fields) | {'columns'}): raise ValueError('Settings contain unknown fields.')
    for key, value in values.items():
        if key == 'columns':
            if not isinstance(value, dict) or any(not isinstance(v, dict) or any(not isinstance(c, str) or not isinstance(x, str) for c, x in v.items()) for v in value.values()): raise ValueError('Column mappings must contain text values.')
            continue
        kind = fields[key]['type']
        valid = isinstance(value, list) and all(isinstance(x, str) for x in value) if kind in {'multiselect', 'template-select'} else isinstance(value, bool) if kind == 'checkbox' else (isinstance(value, (int, float)) and not isinstance(value, bool) or value == '') if kind == 'number' else isinstance(value, str)
        if not valid: raise ValueError('Invalid setting type: ' + key)
    return {'ok': True}


def example(module, design='parallel', summary_type='ae'):
    reset()
    values = {'study_id':'SYNTHETIC-QC', 'columns': {}}
    if module in {'r_tlf','sas_tlf'}:
        if design not in {'parallel','crossover','single_sequence','sad','mad'}: raise ValueError('Unknown example design.')
        feeds = json.loads((ROOT/'browser_modules/workbench/example-inputs.json').read_text())[design]
        values.update(design=design,outputs=['t_disposition'],profile_days='1, 14' if design=='mad' else '1',analysis_day=14 if design=='mad' else 1,
            dose_map='Placebo=0\nDose 10=10\nDose 20=20\nDose 40=40' if design in {'sad','mad'} else 'Placebo=0\nTest=10\nReference=10',meddra='Synthetic uncoded terms',whodrug='Synthetic uncoded terms')
    elif module=='sas_monitor':
        feeds={'liver':'USUBJID,alt_x,ast_x,tbl_x,alp_x\nP1,3,1,2.1,1\nP2,1,1,1,1\n',
          'qtcf':'USUBJID,QTCF,DQTCF\nP1,501,61\nP2,480,30\n',
          'ae':'USUBJID,COHORT,AESER,AETOXGR,TRTEMFL\nP1,A,Y,3,Y\nP2,A,N,1,Y\n',
          'dlt':'USUBJID,COHORT,DLT_EVAL,DLTFL\nP1,A,Y,Y\nP2,A,Y,N\nP3,A,Y,N\n',
          'enrollment':'N_ENROLLED,N_PLANNED_TO_DATE\n8,12\n',
          'queries':'OPEN_FL,QUERY_AGE_DAYS\nY,31\nN,40\n',
          'visits':'USUBJID,VISIT,ACTDT,PLANDT,WINDOW_DAYS\nP1,V1,2026-01-07,2026-01-01,3\nP2,V1,,2026-01-01,3\n',
          'clinical':'USUBJID,TRT01P\nP1,A\nP2,B\n','randomization':'USUBJID,IXRS_TRT\nP1,A\nP2,A\n'}
        values.update(checks=list(guided_modules.CHECKS),analysis_date='2026-01-15')
    elif module=='interpretation':
        feeds={'ae_summary':'category,n,pct\nAny TEAE,5,50\nRelated TEAE,2,20\nSevere TEAE,1,10\nSAE,1,10\nTEAE leading to discontinuation,0,0\nDeath,0,0\n',
            'pk_summary':'trt,param,n,geomean,geocv,median\nTest,CMAX,12,10.5,22.4,10.2\n'}
        values.update(summary_type=summary_type,arm='Test',population_n=10,treatment='Test',parameter='CMAX')
    else:
        feeds={'findings':'finding_id,rule,findtext\nF1,Query age,Two open queries exceed the reviewed threshold.\nF2,Visit window,One expected visit remains missing at the data cut.\n'}
    metadata={}
    for slot, content in feeds.items():
        metadata[slot]=import_csv(module,slot,'SYNTHETIC-'+slot+'.csv',base64.b64encode(content.encode()).decode())
        values['columns'][slot]={c:c for c in metadata[slot]['columns']}
    return {'values':values,'inputs':metadata,'synthetic':True}


def reset():
    shutil.rmtree(SESSION, ignore_errors=True)
    SESSION.mkdir(parents=True, exist_ok=True)
    return {'cleared': True}


def import_csv(module, slot, name, encoded):
    spec = schema(module)
    if slot not in {s['id'] for s in spec['inputs']}:
        raise ValueError('Unknown input feed.')
    target = SESSION / 'inputs' / (slot + '.csv')
    target.unlink(missing_ok=True)  # Rejected replacement never preserves old input.
    data = base64.b64decode(encoded, validate=True)
    if len(data) > MAX_BYTES:
        raise ValueError('Each CSV may contain at most 16 MiB.')
    text = data.decode('utf-8-sig')
    reader = csv.reader(io.StringIO(text, newline=''), strict=True)
    columns = next(reader, None)
    if not columns or any(not x.strip() for x in columns) or len(set(columns)) != len(columns):
        raise ValueError('CSV headers must be nonempty and unique.')
    rows, preview = 0, []
    for record in reader:
        if len(record) != len(columns):
            raise ValueError('CSV records must have exactly the header column count.')
        rows += 1
        if rows > MAX_ROWS:
            raise ValueError('Each CSV may contain at most 100,000 rows. Use a prespecified analysis subset, never drop eligible records to satisfy a software limit.')
        if rows <= 5:
            preview.append(record)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    return {'slot': slot, 'filename': str(name)[:200], 'absolute_path': str(target),
            'path': 'inputs/' + target.name, 'columns': columns, 'rows': rows,
            'preview': preview, 'sha256': hashlib.sha256(data).hexdigest()}


def inputs_for(module):
    result = {}
    for slot in schema(module)['inputs']:
        path = SESSION / 'inputs' / (slot['id'] + '.csv')
        if path.is_file():
            with path.open(encoding='utf-8-sig', newline='') as handle:
                r = csv.reader(handle, strict=True); columns = next(r)
                count = sum(1 for _ in r)
            result[slot['id']] = {'absolute_path': str(path), 'path': 'inputs/' + path.name,
                'filename': path.name, 'columns': columns, 'rows': count,
                'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    return result


def selected_inputs(module, values):
    spec=schema(module);needed=set();selection=False
    for step in spec['steps']:
        for field in step.get('fields', []):
            options=field.get('options_by_design',{}).get(values.get(field.get('depends_on')),field.get('options',[]))
            selected=values.get(field['id'],field.get('default',[]))
            selected=selected if isinstance(selected,list) else [selected]
            for option in options:
                if 'inputs' in option:
                    selection=True
                    if option['value'] in selected: needed.update(option['inputs'])
    known={slot['id'] for slot in spec['inputs']}
    return {key:value for key,value in inputs_for(module).items() if key in (needed if selection else known)}


def validate(module, values):
    check_profile(module, values)
    if module == 'localmind':
        # Browser inference is configured separately; never contact loopback.
        values = dict(values, enable_model=False)
    active_inputs=selected_inputs(module,values)
    values=dict(values,columns={key:mapping for key,mapping in values.get('columns',{}).items() if key in active_inputs})
    report = provider(module).validate(module, values, active_inputs, ROOT)
    if module == 'localmind': report['warnings'] = ['All labels and model suggestions remain unapproved. Browser inference is an optional explicit action after preparing the review worklist.']
    return report


def build(module, values):
    checked = validate(module, values)
    if checked['errors']:
        return {'ok': False, 'validation': checked}
    active_inputs=selected_inputs(module,checked['normalized'])
    built = provider(module).build(module, checked['normalized'], active_inputs, ROOT)
    files = dict(built['files'])
    files['setup_profile.json'] = json.dumps({'schema': 1, 'module_id': module, 'values': checked['normalized']}, indent=2)
    for relative in ['toolkit_launcher/analysis_runner.R', 'toolkit_launcher/analysis_monitor.R', 'assets/theme/tokens.css']:
        files[relative] = (ROOT / relative).read_text(encoding='utf-8')
    for slot, meta in active_inputs.items():
        files['uploads/' + slot + '.csv'] = Path(meta['absolute_path']).read_text(encoding='utf-8-sig')
    files['BROWSER_START_HERE.txt'] = 'These results were computed inside the browser. Open analysis_report.html after extracting the complete ZIP. The configuration folder retains original source and optional desktop reproduction instructions. Review numerical results, assumptions, diagnostics and input fingerprints. No scientific approval or native SAS execution is implied.\n'
    files['browser_input_inventory.json'] = json.dumps({'inputs': active_inputs, 'approved': False}, indent=2)
    answer = {'ok': True, 'files': files, 'validation': checked, 'summary': built['summary'], 'limitations': built['limitations']}
    if module == 'localmind': answer['review'] = {'rows': list(csv.DictReader(io.StringIO(files['inputs/findings.csv']))), 'labels': {key: checked['normalized'][key+'_labels'].splitlines() for key in ['owner','severity','novelty']}}
    return answer


def call(operation, payload):
    if operation == 'reset': return reset()
    if operation == 'check-profile': return check_profile(payload['module'],payload['values'])
    if operation == 'example': return example(payload['module'],payload.get('design','parallel'),payload.get('summary_type','ae'))
    if operation == 'schema': return schema(payload['module'])
    if operation == 'upload': return import_csv(payload['module'], payload['slot'], payload['name'], payload['base64'])
    if operation == 'remove':
        slot = payload['slot']
        if slot not in {x['id'] for x in schema(payload['module'])['inputs']}: raise ValueError('Unknown input feed.')
        (SESSION / 'inputs' / (slot + '.csv')).unlink(missing_ok=True)
        return {'removed': slot}
    if operation == 'validate': return validate(payload['module'], payload['values'])
    if operation == 'build': return build(payload['module'], payload['values'])
    raise ValueError('Unknown browser operation.')
