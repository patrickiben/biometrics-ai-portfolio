"""biostat_pipeline/build_print.py: the printable handbook and the poster map, generated from pipeline.json.

Called by build_v2.py. write_all() writes handbook.html and poster.html to a temporary folder; render_pdfs() prints them to
EarlyPhase_Biostat_Pipeline.pdf (the handbook) and EarlyPhase_Biostat_Pipeline_Map.pdf with headless Google Chrome.
"""
import html, os, shutil, subprocess

E = html.escape
STAGE_INTRO = {
    1: 'Biostatistics shapes the design: objectives and estimands, endpoints, the sample-size basis, randomization, decision rules and the statistical sections of the protocol.',
    2: 'Everything is specified before data arrive: the SAP, table shells, dataset specifications, the randomization schedule, the data-review plan and the QC plan.',
    3: 'Collected data become standardized, conformant, traceable CDISC datasets with reviewer guides and Define-XML, and the database is locked under documented controls.',
    4: 'Tables, listings, figures and PK analyses are produced from the locked data, independently checked, and every reported number traces to a qualified program.',
    5: 'Results become the clinical study report and its appendices, the submission data package, public results postings and the archived study record.',
}
STAGE_COLOR = {1: '#2f6fd6', 2: '#7a52c7', 3: '#0f8f84', 4: '#b7791f', 5: '#2f8f4e'}
URL = 'https://patrickiben.github.io/biometrics-ai-portfolio/biostat_pipeline/'


def _milestones_svg(D, width=980):
    M = D['milestones']
    n = len(M)
    step = (width - 40) / (n - 1)
    out = [f'<svg viewBox="0 0 {width} 120" width="100%" role="img" aria-label="Milestones from protocol development to archiving">',
           f'<line x1="20" y1="38" x2="{width - 20}" y2="38" stroke="#9aa4b2" stroke-width="2"/>']
    for i, m in enumerate(M):
        x = 20 + i * step
        if m.get('gate'):
            out.append(f'<rect x="{x - 9}" y="29" width="18" height="18" rx="3" fill="#0f8f84" transform="rotate(45 {x} 38)"/>')
        else:
            out.append(f'<circle cx="{x}" cy="38" r="6" fill="#ffffff" stroke="#5b6878" stroke-width="2"/>')
        out.append(f'<text x="{x}" y="16" text-anchor="middle" font-family="Menlo, monospace" font-size="11" font-weight="700" fill="#4d5a69">{E(m["id"])}</text>')
        words, lines, cur = m['label'].split(), [], ''
        for w in words:
            if len(cur) + len(w) + 1 > 14 and cur:
                lines.append(cur)
                cur = w
            else:
                cur = (cur + ' ' + w).strip()
        lines.append(cur)
        for k, ln in enumerate(lines[:4]):
            out.append(f'<text x="{x}" y="{66 + k * 13}" text-anchor="middle" font-size="10.5" fill="#1f2a37">{E(ln)}</text>')
    out.append('</svg>')
    return ''.join(out)


CSS = """
@page { size: Letter; margin: 0.6in 0.62in 0.72in; @bottom-right { content: counter(page); font: 9pt Menlo, monospace; color: #5b6878; }
        @bottom-left { content: "Early-phase biostatistics deliverables pipeline"; font: 8.5pt -apple-system, Helvetica, Arial, sans-serif; color: #5b6878; } }
@page :first { @bottom-right { content: none; } @bottom-left { content: none; } }
* { box-sizing: border-box; }
body { margin: 0; font: 9.6pt/1.45 -apple-system, "Segoe UI", Helvetica, Arial, sans-serif; color: #1f2a37; }
h1, h2, h3, h4 { color: #121a24; margin: 0; }
.mono, .id { font-family: "SF Mono", Menlo, Consolas, monospace; }
.kick { font: 700 8pt/1.3 "SF Mono", Menlo, monospace; letter-spacing: .16em; text-transform: uppercase; color: #8a5300; }
.cover { height: 9.4in; display: flex; flex-direction: column; justify-content: space-between; page-break-after: always; }
.cover .top { border-top: 6px solid #0f8f84; padding-top: 18px; }
.cover h1 { font-size: 30pt; line-height: 1.12; margin: 14px 0 12px; letter-spacing: -.01em; }
.cover .sub { font-size: 13pt; color: #4d5a69; max-width: 6in; }
.facts { display: grid; grid-template-columns: repeat(4, 1fr); gap: 10px; margin: 26px 0 0; }
.facts div { border: 1px solid #d7dee7; border-left: 4px solid #0f8f84; border-radius: 6px; padding: 10px 12px; }
.facts b { display: block; font-size: 20pt; color: #121a24; }
.facts span { font-size: 9pt; color: #4d5a69; }
.cover .bottom { font-size: 9pt; color: #4d5a69; border-top: 1px solid #d7dee7; padding-top: 10px; }
.stagebar { display: flex; gap: 4px; margin-top: 26px; }
.stagebar div { flex: 1; padding: 9px 10px; border-radius: 5px; color: #fff; font-size: 9pt; }
.stagebar b { display: block; font-size: 10.5pt; }
section.chap { page-break-before: always; }
h2.ch { font-size: 19pt; margin: 4px 0 6px; }
h3 { font-size: 12.5pt; margin: 16px 0 6px; }
p { margin: 0 0 7px; }
.lede { font-size: 10.5pt; color: #4d5a69; max-width: 6.6in; }
table { width: 100%; border-collapse: collapse; margin: 6px 0 12px; font-size: 8.8pt; }
th, td { text-align: left; vertical-align: top; padding: 4px 6px; border-bottom: 1px solid #e4e9ef; }
th { font: 700 7.6pt "SF Mono", Menlo, monospace; letter-spacing: .06em; text-transform: uppercase; color: #4d5a69; background: #f4f6f9; }
td.id, td .id { white-space: nowrap; font-weight: 700; }
.card { break-inside: avoid; border: 1px solid #d7dee7; border-left: 4px solid var(--c); border-radius: 6px; padding: 9px 11px 7px; margin: 0 0 9px; }
.card h4 { font-size: 11pt; line-height: 1.3; margin: 0 0 3px; }
.card h4 .id { color: var(--c); margin-right: 6px; }
.meta { font-size: 8.4pt; color: #4d5a69; margin: 0 0 5px; }
.meta span + span::before { content: " · "; }
.grid2 { display: grid; grid-template-columns: 1fr 1fr; gap: 2px 16px; }
.lab { font: 700 7.4pt "SF Mono", Menlo, monospace; letter-spacing: .08em; text-transform: uppercase; color: #5b6878; margin: 4px 0 1px; }
.card p { margin: 0 0 3px; font-size: 9pt; }
.card ul { margin: 0 0 3px; padding-left: 1.1em; font-size: 9pt; }
.ids { font-family: "SF Mono", Menlo, monospace; font-size: 8.3pt; color: #1f2a37; }
.cond { display: inline-block; border: 1px dashed #8a5300; color: #8a5300; border-radius: 3px; padding: 0 5px; font: 700 7.4pt "SF Mono", Menlo, monospace; text-transform: uppercase; }
.wk { display: inline-block; background: #e3f2e8; color: #1d6b3c; border-radius: 3px; padding: 0 5px; font: 700 7.4pt "SF Mono", Menlo, monospace; text-transform: uppercase; }
.legend td:first-child { width: 1.4in; font-weight: 700; }
.small { font-size: 8.6pt; color: #4d5a69; }
a { color: #0b7268; text-decoration: none; }
.stagehead { border-top: 6px solid var(--c); padding-top: 10px; }
"""


def handbook_html(D, R, REFS, refs_used, cited):
    st = {s['n']: s for s in D['stages']}
    mlab = {m['id']: m['label'] for m in D['milestones']}
    dname = {x['code']: x['name'] for x in D['designs']}
    feeds = {r['id']: [] for r in R}
    for r in R:
        for p in r['depends_on']:
            feeds[p].append(r['id'])

    def worked(r):
        return any(t['label'].lower().startswith('worked study') for t in r['toolkit'])

    def designs(r):
        return 'All designs' if r['designs'] == ['all'] else ', '.join(dname[c] for c in r['designs'])

    def reftitle(k):
        f = REFS[k]
        return f.get('short') or f['title']

    gates = sum(1 for m in D['milestones'] if m.get('gate'))
    o = [f'<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Early-phase biostatistics deliverables pipeline: handbook</title><style>{CSS}</style></head><body>']
    # cover
    sb = ''.join(f'<div style="background:{STAGE_COLOR[s["n"]]}"><b>{s["n"]}. {E(s["name"])}</b>closes at {E(mlab[s["gate"]])}</div>' for s in D['stages'])
    o.append(f'''<div class="cover"><div class="top"><p class="kick">Trial biostatistics toolkit · Planning reference</p>
<h1>Protocol to CSR: the early-phase biostatistics deliverables pipeline</h1>
<p class="sub">Every statistics deliverable of an early-phase clinical-pharmacology study, from protocol development to the clinical study report, results posting and archiving: owner, inputs, what it feeds, governing standard, quality control and common pitfalls.</p>
<div class="facts"><div><b>{len(R)}</b><span>deliverables</span></div><div><b>{len(D["stages"])} · {gates}</b><span>stages · gates</span></div>
<div><b>{len(D["designs"])}</b><span>study designs</span></div><div><b>{len(refs_used)}</b><span>references checked {E(D.get("refs_checked_on", ""))}</span></div></div>
<div class="stagebar">{sb}</div></div>
<div class="bottom">A planning reference for a biostatistics consultant or lead biostatistician, not a record of client work, an SOP or a validated system. Adapt it to the protocol, the client's SOPs and the regulations that apply. The interactive explorer, the poster map and the Excel register hold the same content: {E(URL)}. Generated {E(D["updated"])} from pipeline.json.</div></div>''')
    # how to read
    o.append('<section class="chap"><p class="kick">Before you start</p><h2 class="ch">How to read this handbook</h2>'
             '<p class="lede">Each deliverable has one card. The card says what the deliverable is and why it matters, what it needs and which deliverables it depends on, what it produces and which deliverables it feeds, how it is checked, the mistakes that cost time later, and the standards that govern it.</p>'
             '<h3>Milestones and gates</h3><p>Every deliverable is placed between two milestones: the point where work on it can start and the point by which it must be final. Diamonds are gates: a stage is complete when its gate is passed.</p>'
             + _milestones_svg(D) +
             '<h3>Tracks</h3><table class="legend"><tbody>' + ''.join(f'<tr><td>{E(t["name"])}</td><td>{sum(1 for r in R if r["track"] == t["name"])} deliverables</td></tr>' for t in D['tracks']) + '</tbody></table>'
             '<h3>Study designs</h3><p>Most deliverables apply to every early-phase study. Design-specific deliverables are marked with the designs they belong to; the design chapters list them together.</p><table class="legend"><tbody>'
             + ''.join(f'<tr><td>{E(x["code"])}</td><td>{E(x["name"])}</td></tr>' for x in D['designs']) + '</tbody></table>'
             '<h3>Field guide</h3><table class="legend"><tbody>'
             '<tr><td>Depends on</td><td>Direct predecessors: deliverables that must exist, at least in draft, before this one can be finished.</td></tr>'
             '<tr><td>Feeds</td><td>Deliverables that list this one as a predecessor. A change here should trigger a check of each of them.</td></tr>'
             '<tr><td><span class="cond">conditional</span></td><td>Applies only in some studies; the card says when.</td></tr>'
             '<tr><td><span class="wk">worked study</span></td><td>The toolkit\'s synthetic bioequivalence study produced this deliverable; its card links to the real output.</td></tr>'
             '</tbody></table></section>')
    # at a glance
    tr = [t['name'] for t in D['tracks']]
    rows = ''.join('<tr><td><b>' + f'{s["n"]}. {E(s["name"])}</b></td>' + ''.join(f'<td>{sum(1 for r in R if r["stage"] == s["n"] and r["track"] == t) or ""}</td>' for t in tr)
                   + f'<td><b>{sum(1 for r in R if r["stage"] == s["n"])}</b></td><td>{E(mlab[s["gate"]])}</td></tr>' for s in D['stages'])
    o.append('<section class="chap"><p class="kick">Overview</p><h2 class="ch">The pipeline at a glance</h2>'
             '<p class="lede">Five stages, each closed by a gate. Rows are stages, columns are tracks; each cell counts the deliverables in that stage and track.</p>'
             '<table><thead><tr><th>Stage</th>' + ''.join(f'<th>{E(t)}</th>' for t in tr) + '<th>Total</th><th>Gate</th></tr></thead><tbody>' + rows + '</tbody></table>'
             '<h3>Longest dependency chains</h3><p class="small">The chains below are the longest paths through the "depends on" links that end at a stage-5 deliverable. They are the order in which delays propagate.</p>'
             + _chains(R) + '</section>')
    # stage chapters
    for s in D['stages']:
        items = [r for r in R if r['stage'] == s['n']]
        c = STAGE_COLOR[s['n']]
        o.append(f'<section class="chap" style="--c:{c}"><div class="stagehead"><p class="kick">Stage {s["n"]} · closes at {E(mlab[s["gate"]])}</p><h2 class="ch">{E(s["name"])}</h2>'
                 f'<p class="lede">{E(STAGE_INTRO[s["n"]])} {len(items)} deliverables.</p></div>'
                 '<table><thead><tr><th>ID</th><th>Deliverable</th><th>Owner</th><th>From → to</th><th>Designs</th></tr></thead><tbody>'
                 + ''.join(f'<tr><td class="id">{E(r["id"])}</td><td>{E(r["title"])}{" <span class=cond>conditional</span>" if r["conditional"] else ""}</td><td>{E(r["owner"])}</td><td class="mono">{E(r["window"][0])} → {E(r["window"][1])}</td><td>{E("All" if r["designs"] == ["all"] else ", ".join(r["designs"]))}</td></tr>' for r in items)
                 + '</tbody></table>')
        for r in items:
            o.append(f'<div class="card" style="--c:{c}"><h4><span class="id">{E(r["id"])}</span>{E(r["title"])}</h4>'
                     f'<p class="meta"><span>{E(r["type"])}</span><span>{E(r["track"])}</span><span>{E(r["owner"])}' + (f' with {E(", ".join(r["contributors"]))}' if r['contributors'] else '') +
                     f'</span><span>{E(mlab[r["window"][0]])} → {E(mlab[r["window"][1]])}</span><span>{E(designs(r))}</span></p>'
                     + (f'<p><span class="cond">conditional</span> {E(r["conditional"])}</p>' if r['conditional'] else '')
                     + f'<p>{E(r["summary"])}</p>' + (f'<p><b>Why it matters.</b> {E(r["why"])}</p>' if r['why'] else '')
                     + '<div class="grid2"><div><p class="lab">Needs</p><p>' + E(r['inputs_text']) + '</p>'
                     + (f'<p class="ids">Depends on: {E(", ".join(r["depends_on"]))}</p>' if r['depends_on'] else '')
                     + '</div><div><p class="lab">Produces</p><p>' + E(r['outputs_text']) + '</p>'
                     + (f'<p class="ids">Feeds: {E(", ".join(feeds[r["id"]]))}</p>' if feeds[r['id']] else '')
                     + '</div></div><p class="lab">Quality control</p><p>' + E(r['qc']) + '</p>'
                     + '<p class="lab">Common pitfalls</p><ul>' + ''.join(f'<li>{E(p)}</li>' for p in r['pitfalls']) + '</ul>'
                     + ('<p class="lab">Standards and guidance</p><ul>' + ''.join(f'<li>{E(reftitle(f["key"]))}' + (f': {E(f["note"])}' if f.get('note') else '') + '</li>' for f in r['refs']) + '</ul>' if r['refs'] else '')
                     + ('<p class="lab">In this toolkit</p><p>' + ' · '.join(f'{E(t["label"])} <span class="small">({E(t["href"])})</span>' for t in r['toolkit']) + (' <span class="wk">worked study</span>' if worked(r) else '') + '</p>' if r['toolkit'] else '')
                     + '</div>')
        o.append('</section>')
    # design chapters
    o.append('<section class="chap"><p class="kick">By design</p><h2 class="ch">Design modules</h2><p class="lede">The deliverables that belong to a particular study design, in addition to the ones every study needs.</p>')
    for x in D['designs']:
        items = [r for r in R if r['designs'] != ['all'] and x['code'] in r['designs']]
        if not items:
            continue
        o.append(f'<h3>{E(x["name"])} ({E(x["code"])})</h3><table><thead><tr><th>ID</th><th>Deliverable</th><th>Stage</th><th>Owner</th></tr></thead><tbody>'
                 + ''.join(f'<tr><td class="id">{E(r["id"])}</td><td>{E(r["title"])}</td><td>{r["stage"]}</td><td>{E(r["owner"])}</td></tr>' for r in items) + '</tbody></table>')
    o.append('</section>')
    # standards index
    o.append(f'<section class="chap"><p class="kick">Sources</p><h2 class="ch">Standards and guidance index</h2><p class="lede">Every reference cited in this handbook, checked against the issuing body\'s own page on {E(D.get("refs_checked_on", ""))}. Confirm the version that applies to your study and submission before relying on it.</p>'
             '<table><thead><tr><th>Reference</th><th>Issuer</th><th>Version, date</th><th>Status</th><th>Cited by</th></tr></thead><tbody>'
             + ''.join(f'<tr><td><b>{E(f["title"])}</b><br><span class="small">{E(f["url"])}</span></td><td>{E(f["issuer"])}</td><td>{E(", ".join(x for x in [f.get("version", ""), f.get("date", "")] if x))}</td><td>{E(f["status"])}' + (f' (see {E(f["superseded_by"])})' if f.get('superseded_by') else '') + f'</td><td class="ids">{cited[f["key"]]}</td></tr>'
                       for f in sorted(refs_used, key=lambda f: (f['issuer'], f['title'])))
             + '</tbody></table></section>')
    o.append('</body></html>')
    return ''.join(o)


def _chains(R):
    by = {r['id']: r for r in R}
    memo = {}

    def longest(i):
        if i in memo:
            return memo[i]
        best = [i]
        for p in by[i]['depends_on']:
            c = longest(p) + [i]
            if len(c) > len(best):
                best = c
        memo[i] = best
        return best
    ends = sorted((longest(r['id']) for r in R if r['stage'] == 5), key=len, reverse=True)
    seen, out = set(), []
    for c in ends:
        if c[-1] in seen or len(c) < 3:
            continue
        seen.add(c[-1])
        out.append('<p class="ids">' + ' → '.join(E(x) for x in c) + '</p>')
        if len(out) == 4:
            break
    return ''.join(out) or '<p class="small">No chains yet.</p>'


def poster_html(D, R, refs_used):
    """One 36 x 24 inch sheet: the five stages across, the seven tracks down, every deliverable in its cell.
    The explorer keeps the timeline view; the handbook has the full cards."""
    stages = D['stages']
    mil = {m['id']: m['label'] for m in D['milestones']}
    tracks = [x['name'] for x in D['tracks']]
    ndes = len(D['designs'])
    cells = {}
    for r in R:
        cells.setdefault((r['track'], r['stage']), []).append(r)
    def chip(r):
        des = [d for d in (r.get('designs') or []) if d != 'all']
        tag = f'<em>{E(" ".join(des))}</em>' if des and len(des) < ndes else ''
        cond = ' cond' if (r.get('conditional') or '').strip() else ''
        return f'<li class="s{r["stage"]}{cond}"><b>{E(r["id"])}</b><span>{E(r["title"])}</span>{tag}</li>'
    head = ''.join(f'<div class="ch s{s["n"]}"><span>Stage {s["n"]}</span><strong>{E(s["name"])}</strong>'
                   f'<small>closes at {E(s["gate"])} · {E(mil.get(s["gate"], ""))}</small></div>' for s in stages)
    rows = []
    for tr in tracks:
        n = sum(len(cells.get((tr, s['n']), [])) for s in stages)
        row = [f'<div class="rh"><strong>{E(tr)}</strong><small>{n} deliverables</small></div>']
        for s in stages:
            items = cells.get((tr, s['n']), [])
            cls = ' two' if len(items) > 16 else ''
            row.append(f'<div class="cell{cls}"><ul>' + ''.join(chip(r) for r in items) + '</ul></div>' if items else '<div class="cell empty"></div>')
        rows.append(''.join(row))
    legend = ''.join(f'<span><i class="s{s["n"]}"></i>Stage {s["n"]} · {E(s["name"])}</span>' for s in stages)
    css = """
@page { size: 36in 24in; margin: 0.4in; }
* { box-sizing: border-box; }
body { margin: 0; font: 15px/1.35 -apple-system, "Helvetica Neue", Helvetica, Arial, sans-serif; color: #121a24; }
.s1 { --c: #2f6fd6; } .s2 { --c: #7a52c7; } .s3 { --c: #0f8f84; } .s4 { --c: #b7791f; } .s5 { --c: #2f8f4e; }
.hd { display: flex; justify-content: space-between; align-items: flex-end; gap: 40px; border-top: 12px solid #0f8f84; padding: 14px 0 6px; }
.k { font: 700 15px Menlo, monospace; letter-spacing: .16em; text-transform: uppercase; color: #8a5300; margin: 0; }
h1 { font-size: 48px; line-height: 1.05; margin: 8px 0 6px; letter-spacing: -.01em; }
.sub { font-size: 19px; color: #3a4654; margin: 0; }
.lg { display: grid; grid-template-columns: repeat(3, auto); gap: 8px 26px; font-size: 16px; color: #1f2a37; }
.lg i { display: inline-block; width: 22px; height: 14px; border-radius: 3px; margin-right: 8px; vertical-align: -2px; background: var(--c); }
.lg i.cd { background: none; border: 2px dashed #5b6878; }
.lg em { font: 700 12px Menlo, monospace; color: #8a5300; background: #fbf1df; border-radius: 3px; padding: 1px 5px; margin-right: 8px; font-style: normal; }
.ms { margin: 0 0 6px; }
.grid { display: grid; grid-template-columns: 2.1in repeat(5, minmax(0, 1fr)); gap: 6px; }
.ch { border-top: 8px solid var(--c); background: #f3f5f8; padding: 8px 12px 9px; border-radius: 0 0 6px 6px; }
.ch span { display: block; font: 700 13px Menlo, monospace; letter-spacing: .12em; text-transform: uppercase; color: var(--c); }
.ch strong { display: block; font-size: 19px; line-height: 1.15; margin: 2px 0; }
.ch small { font-size: 14px; color: #4d5a69; }
.corner { padding: 8px 4px; font-size: 14px; color: #4d5a69; align-self: end; }
.rh { background: #121a24; color: #fff; border-radius: 6px; padding: 10px 12px; }
.rh strong { display: block; font-size: 18px; line-height: 1.2; }
.rh small { font-size: 13px; color: #c9d2dc; }
.cell { border: 1px solid #d9dee5; border-radius: 6px; padding: 5px 6px; background: #fff; min-width: 0; }
.cell.empty { background: repeating-linear-gradient(135deg, #f7f8fa 0 8px, #fff 8px 16px); }
.cell ul { list-style: none; margin: 0; padding: 0; }
.cell.two ul { columns: 2; column-gap: 12px; }
.cell li { display: flex; align-items: baseline; gap: 6px; min-width: 0; padding: 1px 4px 1px 6px; margin: 0 0 1px; border-left: 4px solid var(--c); break-inside: avoid; line-height: 1.25; }
.cell li.cond { border-left-style: dashed; background: #fafbfc; }
.cell li b { font: 700 12px Menlo, monospace; color: var(--c); flex: none; }
.cell li span { flex: 1 1 auto; min-width: 0; font-size: 13px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.cell li em { flex: none; font: 700 10px Menlo, monospace; color: #8a5300; background: #fbf1df; border-radius: 3px; padding: 1px 4px; font-style: normal; }
.ft { display: flex; justify-content: space-between; gap: 40px; margin-top: 12px; padding-top: 10px; border-top: 1px solid #d9dee5; font-size: 14px; color: #4d5a69; }
.ft b { color: #121a24; }
"""
    return ('<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Early-phase biostatistics deliverables pipeline: map</title>'
            f'<style>{css}</style></head><body>'
            f'<div class="hd"><div><p class="k">Trial biostatistics toolkit · Planning reference</p>'
            f'<h1>Protocol to CSR: {len(R)} early-phase biostatistics deliverables</h1>'
            f'<p class="sub">{len(stages)} stages and {sum(1 for m in D["milestones"] if m.get("gate"))} gates · {len(tracks)} tracks · {ndes} study designs · '
            f'{len(refs_used)} standards checked against their sources on {E(D.get("refs_checked_on", ""))}</p></div>'
            f'<div class="lg">{legend}<span><i class="cd"></i>Conditional deliverable</span><span><em>BE</em>Design-specific (all designs if untagged)</span></div></div>'
            f'<div class="ms">{_milestones_svg(D, width=2600)}</div>'
            f'<div class="grid"><div class="corner">Track ↓ · Stage →</div>{head}{"".join(rows)}</div>'
            f'<div class="ft"><span>Each cell lists what a track produces in a stage; ids match the explorer, the handbook and the Excel register, '
            f'which hold the owner, inputs, dependencies, standard, QC and pitfalls of every deliverable. Interactive version: <b>{E(URL)}</b></span>'
            f'<span>A planning reference, not a record of client work or an SOP. Generated {E(D["updated"])}.</span></div>'
            '</body></html>')


def write_all(D, R, REFS, refs_used, cited, out_dir):
    """Write handbook.html and poster.html into out_dir (a temporary folder; they are print sources, not site pages)."""
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, 'handbook.html'), 'w', encoding='utf-8') as f:
        f.write(handbook_html(D, R, REFS, refs_used, cited))
    with open(os.path.join(out_dir, 'poster.html'), 'w', encoding='utf-8') as f:
        f.write(poster_html(D, R, refs_used))


CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'


def render_pdfs(src_dir, here):
    """Print the handbook and poster to PDF. The file names are the ones the site has always published,
    so existing links open the new versions."""
    chrome = CHROME if os.path.exists(CHROME) else (shutil.which('google-chrome') or shutil.which('chromium'))
    if not chrome:
        print('PDFs skipped: Google Chrome not found')
        return
    for src, out in (('handbook.html', 'EarlyPhase_Biostat_Pipeline.pdf'), ('poster.html', 'EarlyPhase_Biostat_Pipeline_Map.pdf')):
        subprocess.run([chrome, '--headless=new', '--disable-gpu', '--no-pdf-header-footer', '--run-all-compositor-stages-before-draw',
                        f'--print-to-pdf={os.path.join(here, out)}', 'file://' + os.path.join(src_dir, src)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print('wrote', out)
