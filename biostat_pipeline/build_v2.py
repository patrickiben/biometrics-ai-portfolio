#!/usr/bin/env python3
"""biostat_pipeline/build_v2.py: one source (pipeline.json), every format.

    python3 biostat_pipeline/build_v2.py            validate, then write the derived files
    python3 biostat_pipeline/build_v2.py --check    validate and fail if a derived text file is out of date (CI)
    python3 biostat_pipeline/build_v2.py --pdf      also render the handbook and poster PDFs (needs Google Chrome)

Derived files: pipeline_data.js (explorer), _register.json (starter for browser_modules/register), the facts line in
index.html, EarlyPhase_Biostat_Pipeline_Register.xlsx (via make_xlsx.js and zip), the handbook and poster print sources (in
a temporary folder) and, with --pdf, EarlyPhase_Biostat_Pipeline.pdf (the handbook) and EarlyPhase_Biostat_Pipeline_Map.pdf
(the poster). Standard library only, except
that the workbook needs node and zip and the PDFs need Chrome.
"""
import html, json, os, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(HERE, 'pipeline.json')
CHECK = '--check' in sys.argv
PDF = '--pdf' in sys.argv
problems, stale = [], []


def fail(msg):
    problems.append(msg)


def rd(p):
    with open(p, encoding='utf-8') as f:
        return f.read()


def put(path, text):
    """Write a derived text file, or record it as stale under --check."""
    old = rd(path) if os.path.exists(path) else None
    if old == text:
        return
    if CHECK:
        stale.append(os.path.relpath(path, ROOT))
    else:
        with open(path, 'w', encoding='utf-8') as f:
            f.write(text)


D = json.loads(rd(SRC))
R = D['records']
MIL = [m['id'] for m in D['milestones']]
MI = {m: i for i, m in enumerate(MIL)}
TRACKS = {t['name'] for t in D['tracks']}
DESIGNS = {x['code'] for x in D['designs']}
TYPES, ROLES = set(D['types']), set(D['roles'])
STAGE = {s['n']: s for s in D['stages']}
REFS = {f['key']: f for f in D.get('refs', [])}
REPO = set()
for dp, dn, fn in os.walk(ROOT):
    dn[:] = [x for x in dn if not x.startswith('.') and x not in ('node_modules', 'renv')]
    for x in fn:
        REPO.add(os.path.relpath(os.path.join(dp, x), ROOT).replace(os.sep, '/'))

# ---------------------------------------------------------------- validation
ids = [r['id'] for r in R]
dups = {i for i in ids if ids.count(i) > 1}
if dups:
    fail('duplicate ids: ' + ', '.join(sorted(dups)))
byid = {r['id']: r for r in R}
REQ = ['id', 'stage', 'title', 'type', 'track', 'owner', 'contributors', 'summary', 'why', 'inputs_text', 'outputs_text',
       'depends_on', 'window', 'designs', 'conditional', 'refs', 'qc', 'pitfalls', 'toolkit']
EMDASH = re.compile('—|&mdash;')
SUBJ = re.compile(r'\bsubjects?\b(?![- ]level analysis dataset)', re.I)
BRIT = re.compile(r'\b(?:modell(?:ing|ed)|licence|organis(?:e|ed|ation)|optimis\w*|colour\w*|behaviour\w*|favour\w*|centre[sd]?|analys(?:e|ed|ing)|randomis\w*|summaris\w*|judgement|programmes?|catalogue[sd]?|labell(?:ed|ing)|artefacts?|normalis\w*)\b', re.I)
for r in R:
    rid = r.get('id', '?')
    for k in REQ:
        if k not in r:
            fail(f'{rid}: missing field {k}')
    if any(k.startswith('ai_') for k in r):
        fail(f'{rid}: AI-use fields are not part of this register')
    if r.get('stage') not in STAGE:
        fail(f'{rid}: stage {r.get("stage")} unknown')
    if r.get('type') not in TYPES:
        fail(f'{rid}: type {r.get("type")!r} not in types')
    if r.get('track') not in TRACKS:
        fail(f'{rid}: track {r.get("track")!r} not in tracks')
    for who in [r.get('owner')] + list(r.get('contributors') or []):
        if who not in ROLES:
            fail(f'{rid}: role {who!r} not in roles')
    w = r.get('window') or []
    if len(w) != 2 or w[0] not in MI or w[1] not in MI or MI[w[0]] > MI[w[1]]:
        fail(f'{rid}: bad window {w}')
    ds = r.get('designs') or []
    if ds != ['all'] and (not ds or any(x not in DESIGNS for x in ds)):
        fail(f'{rid}: bad designs {ds}')
    for p in r.get('depends_on') or []:
        if p not in byid:
            fail(f'{rid}: depends_on {p} does not exist')
        if p == rid:
            fail(f'{rid}: depends on itself')
    for f in r.get('refs') or []:
        if f.get('key') not in REFS:
            fail(f'{rid}: reference key {f.get("key")!r} is not in the verified table')
    for t in r.get('toolkit') or []:
        if t.get('href', '').split('#')[0] not in REPO:
            fail(f'{rid}: toolkit link {t.get("href")!r} is not a file in the repository')
    if not (1 <= len(r.get('pitfalls') or []) <= 3):
        fail(f'{rid}: needs 1 to 3 pitfalls')
    text = ' '.join(str(r.get(k, '')) for k in ('title', 'summary', 'why', 'inputs_text', 'outputs_text', 'qc', 'conditional'))
    text += ' ' + ' '.join(r.get('pitfalls') or []) + ' ' + ' '.join(f.get('note', '') for f in r.get('refs') or [])
    if EMDASH.search(text):
        fail(f'{rid}: em dash in text')
    if SUBJ.search(text.replace('USUBJID', '').replace('SUBJID', '')):
        fail(f'{rid}: "subject" in prose (use participant)')
    if BRIT.search(text):
        fail(f'{rid}: British spelling: {BRIT.search(text).group(0)}')
# acyclic
indeg = {i: 0 for i in byid}
for r in R:
    for p in r.get('depends_on') or []:
        if p in byid:
            indeg[r['id']] += 1
kids = {i: [] for i in byid}
for r in R:
    for p in r.get('depends_on') or []:
        if p in kids:
            kids[p].append(r['id'])
queue = [i for i, n in indeg.items() if n == 0]
seen = 0
while queue:
    n = queue.pop()
    seen += 1
    for c in kids[n]:
        indeg[c] -= 1
        if indeg[c] == 0:
            queue.append(c)
if seen != len(byid):
    fail('dependency graph has a cycle among: ' + ', '.join(sorted(i for i, n in indeg.items() if n > 0))[:400])
for f in REFS.values():
    for k in ('key', 'title', 'issuer', 'url', 'status'):
        if not f.get(k):
            fail(f'reference {f.get("key")}: missing {k}')

if problems:
    print('build_v2.py: ' + str(len(problems)) + ' problem(s):\n  ' + '\n  '.join(problems[:80]))
    sys.exit(1)

# ---------------------------------------------------------------- derived data
cited = {k: 0 for k in REFS}
for r in R:
    for f in r['refs']:
        cited[f['key']] += 1
refs_used = [f for k, f in REFS.items() if cited[k]]
pub = dict(schema=D['schema'], updated=D['updated'], refs_checked_on=D.get('refs_checked_on', ''),
           stages=D['stages'], milestones=D['milestones'], tracks=D['tracks'], designs=D['designs'],
           records=R, refs=refs_used)
put(os.path.join(HERE, 'pipeline_data.js'),
    '/* Generated by build_v2.py from pipeline.json. Edit pipeline.json, not this file. */\nwindow.PIPELINE_DATA = '
    + json.dumps(pub, ensure_ascii=False, separators=(',', ':')) + ';\n')


def std_text(r):
    return '; '.join((REFS[f['key']].get('short') or REFS[f['key']]['title']) for f in r['refs'])


flat = [dict(id=r['id'], stage=f'Stage {r["stage"]}: {STAGE[r["stage"]]["name"]}', deliverable=r['title'], type=r['type'],
             description=r['summary'], owner=r['owner'], inputs=r['inputs_text'], outputs=r['outputs_text'],
             standard=std_text(r), qc=r['qc']) for r in R]
put(os.path.join(HERE, '_register.json'), json.dumps(flat, ensure_ascii=False, indent=1) + '\n')

n_designs = len(D['designs'])
facts = (f'\n    <p class="meta"><span class="st st-note">{len(R)} deliverables</span>'
         f'<span class="st st-note">{len(D["stages"])} stages, {sum(1 for m in D["milestones"] if m.get("gate"))} gates</span>'
         f'<span class="st st-note">{n_designs} study designs</span>'
         f'<span class="st st-note">{len(refs_used)} references checked {html.escape(D.get("refs_checked_on", ""))}</span></p>\n    ')
idx = os.path.join(HERE, 'index.html')
page = rd(idx)
page2 = re.sub(r'(<!-- pipeline:facts -->)(.*?)(<!-- /pipeline:facts -->)', lambda m: m.group(1) + facts + m.group(3), page, flags=re.S)
put(idx, page2)

if CHECK:
    if stale:
        print('build_v2.py --check: out of date: ' + ', '.join(stale) + '. Run python3 biostat_pipeline/build_v2.py.')
        sys.exit(1)
    print(f'build_v2.py --check: {len(R)} deliverables valid; {len(refs_used)} references cited; derived files current.')
    sys.exit(0)

# ---------------------------------------------------------------- workbook (node make_xlsx.js + zip)
def workbook():
    if not shutil.which('node') or not shutil.which('zip'):
        print('workbook skipped: node and zip are needed')
        return
    feeds = {i: [] for i in byid}
    for r in R:
        for p in r['depends_on']:
            feeds[p].append(r['id'])
    mlab = {m['id']: m['label'] for m in D['milestones']}
    head = ['ID', 'Stage', 'Deliverable', 'Type', 'Track', 'Owner', 'Contributors', 'From', 'To', 'Designs', 'Conditional',
            'What it is', 'Why it matters', 'Inputs', 'Depends on', 'Outputs', 'Feeds', 'Standards and guidance', 'QC',
            'Pitfalls', 'In the toolkit', 'Status', 'Due date', 'Study notes']
    rows = [[r['id'], f'{r["stage"]}. {STAGE[r["stage"]]["name"]}', r['title'], r['type'], r['track'], r['owner'],
             ', '.join(r['contributors']), mlab[r['window'][0]], mlab[r['window'][1]],
             'All' if r['designs'] == ['all'] else ', '.join(r['designs']), r['conditional'], r['summary'], r['why'],
             r['inputs_text'], ', '.join(r['depends_on']), r['outputs_text'], ', '.join(feeds[r['id']]),
             '; '.join(REFS[f['key']]['title'] + (f' ({f["note"]})' if f.get('note') else '') for f in r['refs']),
             r['qc'], ' | '.join(r['pitfalls']), ' | '.join(t['label'] for t in r['toolkit']), '', '', ''] for r in R]
    ref_head = ['Key', 'Title', 'Issuer', 'Identifier', 'Version', 'Date', 'Status', 'Superseded by', 'URL', 'Cited by']
    ref_rows = [[f['key'], f['title'], f['issuer'], f.get('identifier', ''), f.get('version', ''), f.get('date', ''),
                 f['status'], f.get('superseded_by', ''), f['url'], cited[f['key']]] for f in refs_used]
    notes = ['Early-phase biostatistics deliverables pipeline: register', '',
             'A planning reference for a biostatistics consultant or lead biostatistician. Adapt it to the study protocol, the client\'s SOPs and the regulations that apply. It is not a record of client work, an SOP or a validated system.',
             'Columns Status, Due date and Study notes are for your own planning. Filter by Designs to keep the deliverables your study needs.',
             f'Reference versions were checked against their issuing bodies on {D.get("refs_checked_on", "")}. Confirm the version that applies to your study and submission.',
             'Source: https://patrickiben.github.io/biometrics-ai-portfolio/biostat_pipeline/ (pipeline.json). Synthetic worked examples only.']
    spec = {'sheets': [
        {'sheet': 'Read me', 'headers': ['Read me'], 'rows': [[x] for x in notes], 'note': True, 'widths': [110]},
        {'sheet': 'Register', 'headers': head, 'rows': rows, 'tierCol': None, 'freezeCols': 3,
         'widths': [8, 22, 38, 14, 18, 20, 22, 18, 18, 12, 22, 60, 45, 45, 18, 45, 18, 60, 45, 60, 30, 14, 12, 30]},
        {'sheet': 'Standards', 'headers': ref_head, 'rows': ref_rows, 'tierCol': None, 'freezeCols': 1,
         'widths': [20, 70, 18, 22, 16, 16, 12, 18, 50, 9]}]}
    with tempfile.TemporaryDirectory() as tmp:
        sj = os.path.join(tmp, 'spec.json')
        with open(sj, 'w', encoding='utf-8') as f:
            json.dump(spec, f, ensure_ascii=False)
        parts = os.path.join(tmp, 'parts')
        subprocess.run(['node', os.path.join(HERE, 'make_xlsx.js'), parts, sj], check=True)
        out = os.path.join(HERE, 'EarlyPhase_Biostat_Pipeline_Register.xlsx')
        if os.path.exists(out):
            os.remove(out)
        subprocess.run(['zip', '-q', '-X', '-r', out, '.'], cwd=parts, check=True)
    print('wrote EarlyPhase_Biostat_Pipeline_Register.xlsx')


workbook()

# ---------------------------------------------------------------- handbook and poster (HTML; PDF with --pdf)
sys.path.insert(0, HERE)
try:
    import build_print  # handbook and poster HTML
    import tempfile
    PRINT_DIR = tempfile.mkdtemp(prefix='pipeline-print-')
    build_print.write_all(D, R, REFS, refs_used, cited, PRINT_DIR)
    print('print sources:', PRINT_DIR)
    if PDF:
        build_print.render_pdfs(PRINT_DIR, HERE)
except ImportError:
    print('handbook and poster skipped: build_print.py not present yet')
print(f'build_v2.py: {len(R)} deliverables, {len(refs_used)} references cited; derived files written.')
