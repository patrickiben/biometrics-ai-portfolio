#!/usr/bin/env python3
"""
Package QC harness — GUI / content-consistency checks across the whole deliverable
package (not just the pseudocode libraries). Catches the failure modes that make a
package hard to use or out of date: broken links, deliverables missing from the
navigation, orphaned pages, terminology drift, forbidden content, and count drift.

Run:  python3 package_qc.py [package_root]     (default: this file's directory)
Exit code 0 if clean, 1 if any issue found. Emits package_qc_report.md.
"""
import os, re, glob, sys, json

ROOT = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
NAV_PAGES = ["START_HERE.html", "index.html", "Operations.html", "Biostatistics.html", "Management.html"]
SKIP_DIR = {"node_modules", "__pycache__"}

def rel(p): return os.path.relpath(p, ROOT)
def read(p):
    try: return open(p, encoding="utf-8", errors="ignore").read()
    except Exception: return ""

issues = {}
def add(cat, msg): issues.setdefault(cat, []).append(msg)

html_files = [f for f in glob.glob(ROOT + "/**/*.html", recursive=True)
              if not any(s in f for s in SKIP_DIR)]

# 1. broken internal links (skip JS template literals ${...}, external, anchors)
for f in html_files:
    base = os.path.dirname(f); t = read(f)
    for m in re.finditer(r'(?:href|src)="([^"]+)"', t):
        u = m.group(1)
        if re.match(r'^(https?:|#|mailto:|tel:|data:|javascript:)', u): continue
        if "${" in u or "'+" in u or "+'" in u: continue          # JS-built href, not static
        p = u.split('#')[0].split('?')[0]
        if not p: continue
        tgt = os.path.normpath(os.path.join(ROOT, p.lstrip('/'))) if p.startswith('/') else os.path.normpath(os.path.join(base, p))
        if not os.path.exists(tgt):
            add("Broken links", f"{rel(f)}  ->  {u}")

# 2. navigation coverage: every top-level deliverable dir must be reachable from the
#    master index (START_HERE.html) AND from at least one hub/section page.
start = read(os.path.join(ROOT, "START_HERE.html"))
hub = "".join(read(os.path.join(ROOT, p)) for p in NAV_PAGES)
deliv_dirs = []
for d in sorted(os.listdir(ROOT)):
    dp = os.path.join(ROOT, d)
    if not os.path.isdir(dp) or d.startswith(("_", ".")) or d in SKIP_DIR or d == "validation_harness": continue  # skip QC infra
    # a "deliverable dir" has at least one html/pdf/xlsx a nav page could link
    if glob.glob(dp + "/*.html") or glob.glob(dp + "/*.pdf") or glob.glob(dp + "/*.xlsx") or glob.glob(dp + "/index.html"):
        deliv_dirs.append(d)
for d in deliv_dirs:
    pat = re.compile(re.escape(d) + r'/')
    if not pat.search(start):
        add("Not in START_HERE (the master index)", d)
    if not pat.search(hub):
        add("Not linked from any hub/section page", d)

# 3. orphaned landing pages: index.html / *_Wiki|Guide|Dashboard|Monitor|Worksheet|Tracker.html
#    that no other page links to (unreachable).
landing = [f for f in html_files if re.search(r'(index|_Wiki|_Guide|Dashboard|Monitor|Worksheet|Tracker|Playbook|Briefing|Exhibit|Digest|Graph|Vault)\.html$', os.path.basename(f), re.I)
           and os.path.dirname(f) != ROOT]
alltext = "".join(read(f) for f in html_files)
for f in landing:
    name = os.path.basename(f); dname = os.path.basename(os.path.dirname(f))
    if not re.search(re.escape(dname) + r'/[^"]*' + re.escape(name), alltext) and (name not in alltext):
        add("Orphaned page (nothing links to it)", rel(f))

# 4. terminology: trial-sense "subject" used as a synonym for participant. Precise patterns
#    so it does NOT flag email subjects, HTML anchor ids (#subjects), CDISC USUBJID, or the
#    course text that teaches the participant-not-subject rule.
TRIAL_SUBJ = re.compile(r'\b(\d+\s+subjects?|per subject|each subject|subject-level|number of subjects|'
                        r'subjects?\s+(were|was|are|is|enrolled|randomi|received|dosed|discontinued|completed|withdrew|per)|'
                        r'the\s+subject\s+(was|is|received|had|enrolled|completed|randomi))\b', re.I)
for f in html_files + glob.glob(ROOT + "/**/*.md", recursive=True):
    if any(s in f for s in SKIP_DIR): continue
    for i, line in enumerate(read(f).splitlines(), 1):
        low = line.lower()
        if TRIAL_SUBJ.search(line) and "usubjid" not in low and "subjid" not in low:
            add("Terminology: 'subject' (use participant)", f"{rel(f)}:{i}")

# 5. forbidden research jargon anywhere. Acronyms match case-sensitively (uppercase
#    only) so minified-JS identifiers like `crt`/`lsa` in bundled libraries (mermaid,
#    bootstrap) don't false-positive; the spelled-out terms stay case-insensitive.
FORB = re.compile(r'(?i:last straw|directedness|critical[ -]transition|world[ -]model|meta-learn)|\b(?:LSA|CRT|JEPA)\b')
for f in html_files + glob.glob(ROOT + "/**/*.md", recursive=True):
    if any(s in f for s in SKIP_DIR): continue
    for i, line in enumerate(read(f).splitlines(), 1):
        if FORB.search(line):
            add("Forbidden research jargon", f"{rel(f)}:{i}")

# 6. count drift: the TLF library count claimed vs actual programs
nsas = len([x for x in glob.glob(ROOT + "/sas_tlf_pseudocode/*/*.sas") if "00_setup" not in x])
nr = len([x for x in glob.glob(ROOT + "/r_tlf_pseudocode/*/*.R") if "00_setup" not in x])
if nsas:
    for f in html_files:
        for m in re.finditer(r'(\d{3})\s*\+\s*(\d{3})', read(f)):
            a, b = int(m.group(1)), int(m.group(2))
            if {a, b} != {nsas} and (200 < a < 260):   # a TLF-library "N + N" claim that disagrees
                if a != nsas or b != nr:
                    add("Count drift (TLF library)", f"{rel(f)}: claims {a}+{b}, actual {nsas}+{nr}")
# course-count consistency
course = os.path.join(ROOT, "courses", "Biostatistics_AI_Training.html")
if os.path.exists(course):
    ct = read(course)
    mm = re.search(r'const SERIES = (\{.*\});', ct)
    if mm:
        try:
            n = len(json.loads(mm.group(1))["courses"])
            for bad in re.finditer(r'(\d+)\s+COURSES', ct):
                if int(bad.group(1)) != n:
                    add("Count drift (courses)", f"courses page claims {bad.group(1)} but SERIES has {n}")
        except Exception: pass

# ---- report ----
total = sum(len(v) for v in issues.values())
lines = ["# Package QC report", "", f"_Scanned {len(html_files)} HTML pages under `{rel(ROOT) or '.'}` — **{total} issue(s)**._", ""]
CAP = 25
for cat in sorted(issues):
    lines.append(f"### {cat} ({len(issues[cat])})")
    for m in issues[cat][:CAP]:
        lines.append(f"- {m}")
    if len(issues[cat]) > CAP: lines.append(f"- …and {len(issues[cat])-CAP} more")
    lines.append("")
if total == 0:
    lines.append("**No issues — package navigation, links, terminology and counts are consistent.**")
open(os.path.join(ROOT, "package_qc_report.md"), "w").write("\n".join(lines))
print("\n".join(lines))
sys.exit(1 if total else 0)
