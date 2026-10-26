#!/usr/bin/env python3
"""
Package QC for the portfolio site: link integrity, navigation, retired content, empty
link cards, terminology, framing and count drift across every published page.

Run:  python3 package_qc.py [package_root] [--external]
  --external   also request every external http(s) link once (no custom headers) and
               report failures as warnings; off by default so CI does not depend on the
               network.
  --all        list every finding (the report otherwise shows 30 per category).
Exit code 0 if clean, 1 if any issue is found. Writes package_qc_report.md next to this
file (the report is a generated artifact and is not committed).

What it checks
  1. Broken local links in HTML (href/src) and Markdown ([text](path)), and links to a
     directory that has no index.html (GitHub Pages answers those with 404).
  2. Retired content: files that were removed from the published site must stay removed,
     no .mp4 is published, and no page links to or names a removed path.
  3. Empty link cards: link containers with no link, and anchors with no text or label.
  4. Navigation: the home page exists, the old entry pages are redirect stubs to it, and
     every top-level module folder is listed in README.md.
  5. Orphaned landing pages that nothing links to.
  6. Terminology: trial-sense "subject" in prose (CDISC USUBJID/SUBJID and the ADaMIG name
     and class of ADSL, "Subject-Level Analysis Dataset", are fine).
  7. Retired framing: the old program brand and employer-only phrases.
  8. Count drift: the TLF library size and the validation-harness gate count.
  9. Style: no em dash in the core pages (home, 404, redirect stubs, README).
 10. Documents: the visible text of every published .xlsx, .docx, .pptx, .pdf and .json file
     gets the framing (7) and terminology (6) checks plus a British-spelling check; em dashes are
     issues in the documents listed in STYLE_DOCS and warnings elsewhere. PDFs need pdftotext
     (poppler-utils); without it they are reported as not scanned.
"""
import glob, html, json, os, re, shutil, subprocess, sys, zipfile
from urllib.parse import unquote

ARGS = [a for a in sys.argv[1:] if not a.startswith('--')]
CHECK_EXTERNAL = '--external' in sys.argv
ROOT = os.path.abspath(ARGS[0]) if ARGS else os.path.dirname(os.path.abspath(__file__))
SKIP_DIR = {'node_modules', '__pycache__', '.git', '.quarto'}

HOME = 'index.html'
REDIRECT_STUBS = []   # Operations, Biostatistics and the full library are the site's own hubs again
CORE_PAGES = [HOME, '404.html', 'README.md', 'Operations.html', 'Biostatistics.html', 'START_HERE.html']
# Removed from the published site (kept in the private archive). Paths are relative to ROOT.
# The consultant toolkit keeps every tool; it drops the management material, onboarding, the training
# course, the narrated videos and the hybrid / on-device AI program wikis (their deterministic macro
# library stays in slm_wiki/macro_library/).
REMOVED = ['New_Hire_Start_Here.html', 'hybrid_ops_wiki/', 'slm_operating_wiki/', 'slm_wiki/SLM_SASR_TrialOps.html',
           'smartsheet_nocode/', 'study_kb_nogui/', 'knowledge_vault/', 'courses/', 'netlify.toml', 'risk_monitor/narration/', 'Management.html',
           'risk_monitor/Trial_Risk_EarlyWarning_Dashboard.html', 'risk_monitor/Advanced_Engine_Manager_Slide.pdf']
RETIRED_FRAMING = re.compile(
    r'AI for Biometrics|pending management approval|our in[- ]house team|in-house capability|'
    r'New biostatistician\? Start here|SVC-BIOSTAT|work laptop|\bper SOP\b|cross-validated SAS|'
    r'Cross.validated SAS|Tested concept: Base SAS|double-programmed SAS you can read|'
    r'no new approval gate|ship this now|layer AI on top when|streamlit\.app|htmlpreview\.github\.io|'
    r'Cloud Claude|API \+ BAA|Max seat|account lead|\bClaude\b|\bBAA\b|Copilot|\bin-house\b|'
    r'hybrid[- ]AI (strategy|governance|policy|routing)|internal hybrid|AI[- ]governance (lead|owner|SOP)', re.I)
# CDISC standard names that contain "subject" and must keep it (variables are already exempt
# through USUBJID/SUBJID): the ADaMIG name and class of ADSL ("Subject-Level Analysis Dataset",
# "SUBJECT LEVEL ANALYSIS DATASET"), which the study/ specification and XPT labels carry.
CDISC_NAMES = re.compile(r'Subject[- ]Level Analysis Dataset', re.I)
TRIAL_SUBJ = re.compile(r'\b(\d+\s+subjects?|per[- ]subject|each subject|subject[- ]level|number of subjects|'
                        r'intra-?subject|inter-?subject|subject (?:data|profiles?)|'
                        r'subjects?\s+(were|was|are|is|enrolled|randomi|received|dosed|discontinued|completed|withdrew|per)|'
                        r'the\s+subject\s+(was|is|received|had|enrolled|completed|randomi))\b', re.I)
BRITISH = re.compile(r'\b(?:re-?)?(?:modell(?:ing|ed|er|ers)|licence[sd]?|organis(?:e|ed|es|ing|ations?)|optimis\w*|'
                     r'colour\w*|behaviour\w*|favour\w*|centre[sd]?|analys(?:e|ed|ing)|randomis\w*|harmonis\w*|summaris\w*|'
                     r'minimis\w*|prioritis\w*|standardis\w*|categoris\w*|characteris(?:e|ed|es|ing)|utilis\w*|recognis\w*|'
                     r'judgement|programmes?|catalogue[sd]?|labell(?:ed|ing)|artefacts?|visualis\w*|normalis\w*|finalis\w*)\b', re.I)
DOC_EXTS = ('.xlsx', '.docx', '.pptx', '.pdf', '.json')
# documents rewritten for the new framing: em dashes there are issues, elsewhere warnings
STYLE_DOCS = ('biostat_pipeline/',)
EM_DASH = re.compile(r'—|&mdash;|&#8212;|&#x2014;', re.I)
HREF = re.compile(r'(?:href|src)\s*=\s*"([^"]+)"')
MD_LINK = re.compile(r'(?<!!)\[[^\]]*\]\(([^)\s]+)\)')
MD_FENCE = re.compile(r'```.*?```', re.S)

issues = {}
warnings = {}


def add(cat, msg):
    issues.setdefault(cat, []).append(msg)


def warn(cat, msg):
    warnings.setdefault(cat, []).append(msg)


def rel(p):
    return os.path.relpath(p, ROOT)


def read(p):
    try:
        return open(p, encoding='utf-8', errors='ignore').read()
    except Exception:
        return ''


def walk(*exts):
    out = []
    for d, dirs, files in os.walk(ROOT):
        dirs[:] = [x for x in dirs if x not in SKIP_DIR]
        for f in files:
            if f.endswith(exts):
                out.append(os.path.join(d, f))
    return sorted(out)


def strip_blocks(t):
    """drop script/style bodies and base64 payloads so text checks see prose and markup only"""
    t = re.sub(r'<(script|style)\b.*?</\1>', ' ', t, flags=re.S | re.I)
    return re.sub(r'data:[a-z/+.-]+;base64,[A-Za-z0-9+/=]+', 'data:', t)


html_files = walk('.html')
md_files = [f for f in walk('.md') if os.path.basename(f) != 'package_qc_report.md']
page_files = [f for f in html_files if not os.path.basename(f).startswith('_')]
externals = set()


def check_target(src_file, url):
    if re.match(r'^(mailto:|tel:|data:|javascript:|blob:|#)', url):
        return
    if re.match(r'^https?://', url):
        externals.add(url.split('#')[0])
        return
    if url.startswith('//') or '${' in url or "'+" in url or "+'" in url or '{{' in url:
        return
    path = unquote(html.unescape(url).split('#')[0].split('?')[0])
    if not path:
        return
    base = os.path.dirname(src_file)
    if path.startswith('/biometrics-ai-portfolio/'):   # the 404 page links from the project site's root
        path = '/' + path[len('/biometrics-ai-portfolio/'):]
    tgt = os.path.normpath(os.path.join(ROOT, path.lstrip('/')) if path.startswith('/') else os.path.join(base, path))
    if not os.path.exists(tgt):
        add('Broken links', f'{rel(src_file)}  ->  {url}')
    elif os.path.isdir(tgt) and not any(os.path.isfile(os.path.join(tgt, n)) for n in ('index.html', 'index.htm')):
        add('Directory link with no index page (404 on Pages)', f'{rel(src_file)}  ->  {url}')


# 1. links ----------------------------------------------------------------------------------
for f in page_files:
    for m in HREF.finditer(strip_blocks(read(f))):
        check_target(f, m.group(1))
for f in md_files:
    t = MD_FENCE.sub('', read(f))
    for m in MD_LINK.finditer(t):
        check_target(f, m.group(1))

# 2. retired content ------------------------------------------------------------------------
for r in REMOVED:
    if os.path.exists(os.path.join(ROOT, r.rstrip('/'))):
        add('Retired content is back in the tree', r)
for f in walk('.mp4', '.MP4'):
    add('Video in the published tree', rel(f))
removed_pat = re.compile('|'.join(re.escape(r) for r in REMOVED if r != 'Management.html') + r'|_narrated\.mp4|\.mp4\b')
for f in page_files + md_files + walk('.qmd'):
    if os.path.basename(f) == 'package_qc.py':
        continue
    t = strip_blocks(read(f)) if f.endswith('.html') else read(f)
    for i, line in enumerate(t.splitlines(), 1):
        if removed_pat.search(line):
            add('Reference to removed content', f'{rel(f)}:{i}')

# 3. empty link cards -----------------------------------------------------------------------
LINK_BOX = re.compile(r'<(div|ul|p|nav)\b[^>]*class="[^"]*\b(links|go|dl|actions)\b[^"]*"[^>]*>(.*?)</\1>', re.S | re.I)
for f in page_files:
    t = strip_blocks(read(f))
    for m in LINK_BOX.finditer(t):
        if '<a ' not in m.group(3) and '<a\n' not in m.group(3):
            add('Empty link container', f'{rel(f)}: <{m.group(1)} class="{m.group(2)}"> holds no link')
    for m in re.finditer(r'<a\b([^>]*)>(.*?)</a>', t, re.S | re.I):
        attrs, inner = m.group(1), m.group(2)
        if 'href=""' in attrs:
            add('Empty link', f'{rel(f)}: <a href="">')
        text = re.sub(r'<[^>]+>', '', inner).strip()
        if attrs.strip() == 'href':   # Quarto code line-number anchors
            continue
        if not text and 'aria-label' not in attrs and '<img' not in inner and '<svg' not in inner and 'aria-hidden' not in attrs:
            add('Link with no text or label', f'{rel(f)}: <a{attrs[:60]}>')

# 4. navigation -----------------------------------------------------------------------------
home = read(os.path.join(ROOT, HOME))
if not home:
    add('Navigation', 'index.html is missing')
for stub in REDIRECT_STUBS:
    t = read(os.path.join(ROOT, stub))
    if not re.search(r'http-equiv="refresh"\s+content="0;\s*url=index\.html"', t):
        add('Navigation', f'{stub} is not a redirect stub to index.html')
readme = read(os.path.join(ROOT, 'README.md'))
for d in sorted(os.listdir(ROOT)):
    dp = os.path.join(ROOT, d)
    if os.path.isdir(dp) and not d.startswith(('.', '_')) and d not in SKIP_DIR:
        if not re.search(re.escape(d) + r'/', readme):
            add('Module folder missing from the README inventory', d)

# 5. orphaned landing pages -----------------------------------------------------------------
linked_text = ''.join(read(f) for f in page_files + md_files)
for f in page_files:
    name, folder = os.path.basename(f), os.path.dirname(f)
    if folder == ROOT or name.startswith('_'):
        continue
    if not re.search(r'(index|Wiki|Guide|guide|Dashboard|dashboard|Monitor|Toolkit|Playbook|Demo|build)\.html$', name):
        continue
    if name not in linked_text.replace(read(f), ''):
        add('Orphaned page (nothing links to it)', rel(f))

# 6. terminology ----------------------------------------------------------------------------
for f in page_files + md_files:
    t = strip_blocks(read(f)) if f.endswith('.html') else read(f)
    for i, line in enumerate(t.splitlines(), 1):
        low = line.lower()
        if TRIAL_SUBJ.search(CDISC_NAMES.sub('', line)) and 'usubjid' not in low and 'subjid' not in low:
            add("Terminology: 'subject' (use participant)", f'{rel(f)}:{i}')

# 7. retired framing ------------------------------------------------------------------------
for f in page_files + md_files + walk('.qmd'):
    if os.path.basename(f) == 'package_qc.py':
        continue
    t = strip_blocks(read(f)) if f.endswith('.html') else read(f)
    for i, line in enumerate(t.splitlines(), 1):
        m = RETIRED_FRAMING.search(line)
        if m:
            add('Retired framing or employer phrase', f'{rel(f)}:{i}: "{m.group(0)}"')

# 8. count drift ----------------------------------------------------------------------------
nsas = len([x for x in glob.glob(ROOT + '/sas_tlf_pseudocode/*/*.sas') if '00_setup' not in x])
nr = len([x for x in glob.glob(ROOT + '/r_tlf_pseudocode/*/*.R') if '00_setup' not in x])
for f in page_files + md_files:
    for m in re.finditer(r'\b(\d{3})\s*\+\s*(\d{3})\b', strip_blocks(read(f))):
        a, b = int(m.group(1)), int(m.group(2))
        if 200 < a < 260 and (a != nsas or b != nr):
            add('Count drift (TLF library)', f'{rel(f)}: claims {a}+{b}, actual {nsas}+{nr}')
ledger = os.path.join(ROOT, 'validation_harness', 'ledger.json')
if os.path.exists(ledger):
    try:
        total = int(json.load(open(ledger)).get('total', 0))
    except Exception:
        total = 0
    words = {6: 'six', 7: 'seven', 8: 'eight', 9: 'nine', 10: 'ten'}
    for f in page_files + md_files:
        t = strip_blocks(read(f))
        for m in re.finditer(r'\b(\d{1,2})/(\d{1,2}) gates?\b|\b(six|seven|eight|nine|ten)[ -](?:named )?gates?\b', t, re.I):
            n = int(m.group(2)) if m.group(2) else {v: k for k, v in words.items()}[m.group(3).lower()]
            if total and n != total:
                add('Count drift (harness gates)', f'{rel(f)}: says "{m.group(0)}", ledger has {total}')

# 9. style in the core pages ----------------------------------------------------------------
for p in CORE_PAGES:
    t = read(os.path.join(ROOT, p))
    for i, line in enumerate(t.splitlines(), 1):
        if EM_DASH.search(line):
            add('Style: em dash in a core page', f'{p}:{i}')

# 10. documents: Office files, PDFs and JSON ----------------------------------------------
OFFICE_PARTS = ('xl/sharedStrings', 'xl/worksheets/sheet', 'word/document', 'word/header', 'word/footer',
                'word/footnotes', 'ppt/slides/slide', 'ppt/notesSlides/')
PDFTOTEXT = shutil.which('pdftotext')


def doc_text(p):
    """visible text of an Office file, PDF or JSON file, one paragraph/row/cell per line; None if unreadable here"""
    ext = os.path.splitext(p)[1].lower()
    if ext == '.json':
        out = []

        def strings(o):
            if isinstance(o, str):
                out.append(o)
            elif isinstance(o, dict):
                for v in o.values():
                    strings(v)
            elif isinstance(o, list):
                for v in o:
                    strings(v)
        try:
            strings(json.load(open(p, encoding='utf-8')))
        except Exception:
            return None
        return '\n'.join(out)
    if ext in ('.xlsx', '.docx', '.pptx'):
        try:
            z = zipfile.ZipFile(p)
        except Exception:
            return None
        out = []
        for n in sorted(z.namelist()):
            if n.endswith('.xml') and (n.startswith(OFFICE_PARTS) or n == 'docProps/core.xml'):
                x = z.read(n).decode('utf-8', 'ignore')
                x = re.sub(r'</(?:a:p|w:p|row|si|c|dc:title|dc:subject|dc:description|cp:keywords)>', '\n', x)
                out.append(html.unescape(re.sub(r'<[^>]+>', '', x)))
        return '\n'.join(out)
    if ext == '.pdf':
        if not PDFTOTEXT:
            return None
        r = subprocess.run([PDFTOTEXT, '-enc', 'UTF-8', p, '-'], capture_output=True, text=True)
        return r.stdout if r.returncode == 0 else None
    return None


for f in walk(*DOC_EXTS):
    if rel(f) == 'validation_harness/ledger.json':   # generated from the checks themselves
        continue
    t = doc_text(f)
    if t is None:
        warn('Document not scanned (unreadable here; PDFs need pdftotext)', rel(f))
        continue
    for i, line in enumerate(t.splitlines(), 1):
        low = line.lower()
        m = RETIRED_FRAMING.search(line)
        if m:
            add('Retired framing or employer phrase', f'{rel(f)} (text line {i}): "{m.group(0)}"')
        if TRIAL_SUBJ.search(CDISC_NAMES.sub('', line)) and 'usubjid' not in low and 'subjid' not in low:
            add("Terminology: 'subject' (use participant)", f'{rel(f)} (text line {i})')
        m = BRITISH.search(line)
        if m:
            add('Style: British spelling in a document', f'{rel(f)} (text line {i}): "{m.group(0)}"')
        if EM_DASH.search(line):
            (add if rel(f).startswith(STYLE_DOCS) else warn)('Style: em dash in a document', f'{rel(f)} (text line {i})')

# optional: external links --------------------------------------------------------------------
if CHECK_EXTERNAL:
    import urllib.request
    for u in sorted(externals):
        try:
            req = urllib.request.Request(u, method='GET')
            with urllib.request.urlopen(req, timeout=20) as r:
                code = r.status
        except Exception as e:
            code = getattr(e, 'code', None) or type(e).__name__
        if not (isinstance(code, int) and code < 400):
            warn('External link not reachable', f'{u}  ({code})')

# report --------------------------------------------------------------------------------------
total_issues = sum(len(v) for v in issues.values())
lines = ['# Package QC report', '',
         f'_Scanned {len(page_files)} HTML pages and {len(md_files)} Markdown files under `{rel(ROOT) or "."}`: '
         f'**{total_issues} issue(s)**' + (f', {sum(len(v) for v in warnings.values())} warning(s)' if warnings else '') + '._', '']
CAP = 10 ** 6 if '--all' in sys.argv else 30
for title, group in (('', issues), ('Warning: ', warnings)):
    for cat in sorted(group):
        lines.append(f'### {title}{cat} ({len(group[cat])})')
        lines.extend(f'- {m}' for m in group[cat][:CAP])
        if len(group[cat]) > CAP:
            lines.append(f'- ...and {len(group[cat]) - CAP} more')
        lines.append('')
if total_issues == 0:
    lines.append('**No issues.** Links resolve, retired content stays retired, link cards are filled, '
                 'navigation and the README inventory are complete, and the checked terms and counts are consistent. '
                 'This checks the package, not the statistics.')
open(os.path.join(ROOT, 'package_qc_report.md'), 'w').write('\n'.join(lines) + '\n')
print('\n'.join(lines))
sys.exit(1 if total_issues else 0)
