#!/usr/bin/env python3
"""
kb_to_vault.py  —  Generate a Markdown knowledge vault from live Study KB entries.

This is the PRODUCTION path behind the curated demo: instead of hand-writing notes,
it reads the operational entries the Study Knowledge Base already produces
(study_kb_nogui / Update-StudyKB.ps1 writes one sanitized .html file per ingested
email) and emits one Obsidian/Foam-ready .md note per entry, plus a per-study hub —
so the graph is GENERATED from real study traffic, not drawn by hand.

How links are generated (no AI, fully deterministic):
  • every note links to its study hub  ([[<study> Knowledge Hub]])
  • notes that share a primary tag link to each other (topic clustering)
The result opens directly in Obsidian/Foam (graph view) or the bundled
Knowledge_Graph.html viewer.

Each KB entry is expected to carry light metadata (Update-StudyKB.ps1 emits these):
  <title> or <h1>            -> note title
  <meta name="study"  ...>   -> study id        (default: CP-101)
  <meta name="date"   ...>   -> ingest/sent date
  <meta name="from"   ...>   -> sender (ops; kept as 'source', not PHI)
  <meta name="tags"   ...>   -> comma-separated topic tags

Usage:
  python3 kb_to_vault.py --kb "~/Study Knowledge Base" --out vault_from_kb
  python3 kb_to_vault.py --demo            # synthesise 6 sample entries + convert (runnable)

GOVERNANCE: operations only. This tool copies ops text into notes; it never invents
a number and never promotes a note to a source of record. Keep PHI / participant-level
/ unblinded content out of the KB in the first place (the inbound mail rule does this).
"""
import argparse, os, re, sys, html, glob, tempfile

META = lambda s, name: (re.search(r'<meta\s+name=["\']'+name+r'["\']\s+content=["\'](.*?)["\']', s, re.I) or [None, ""])[1]

def parse_entry(path):
    s = open(path, encoding="utf-8", errors="replace").read()
    title = (re.search(r"<h1[^>]*>(.*?)</h1>", s, re.I|re.S) or
             re.search(r"<title[^>]*>(.*?)</title>", s, re.I|re.S))
    title = html.unescape(re.sub(r"<[^>]+>", "", title.group(1)).strip()) if title else os.path.splitext(os.path.basename(path))[0]
    study = META(s, "study") or "CP-101"
    date  = META(s, "date")  or ""
    sender= META(s, "from")  or ""
    tags  = [t.strip().lower() for t in (META(s, "tags") or "").split(",") if t.strip()]
    # body: take <body> only, strip scripts/styles/tags, collapse whitespace
    bm = re.search(r"<body[^>]*>(.*?)</body>", s, re.I|re.S)
    src = bm.group(1) if bm else s
    src = re.sub(r"<(script|style)[^>]*>.*?</\1>", "", src, flags=re.I|re.S)
    body = html.unescape(re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", src))).strip()
    while body.lower().startswith(title.lower()):   # drop title echo(es)
        body = body[len(title):].strip(" -–—:")
    return {"title": title, "study": study, "date": date, "from": sender,
            "tags": tags or ["general"], "body": body[:600], "file": os.path.basename(path)}

def slug(t):
    return re.sub(r'[\\/:*?"<>|]', "-", t).strip()

def write_vault(entries, out):
    os.makedirs(out, exist_ok=True)
    study = entries[0]["study"] if entries else "CP-101"
    hub_title = f"{study} Knowledge Hub"
    # tag -> entry titles (for cross-links)
    by_tag = {}
    for e in entries:
        by_tag.setdefault(e["tags"][0], []).append(e["title"])
    written = []
    for e in entries:
        related = [t for t in by_tag.get(e["tags"][0], []) if t != e["title"]][:6]
        rel_block = "\n".join(f"- [[{r}]]" for r in related) or "- _(no sibling notes on this topic yet)_"
        fm = ("---\n"
              f"title: {e['title']}\n"
              f"study: {e['study']}\n"
              f"type: kb-entry\n"
              f"date: {e['date']}\n"
              f"source: {e['from']}\n"
              f"tags: [{', '.join(['kb-entry']+e['tags'])}]\n"
              f"origin: {e['file']}\n"
              "note: informational ops support — NOT a source of record\n"
              "---\n")
        md = (f"{fm}\n# {e['title']}\n\n{e['body'] or '_(operational note)_'}\n\n"
              f"## Topic\n`{e['tags'][0]}`\n\n"
              f"## Related\n- [[{hub_title}]] — study home\n{rel_block}\n")
        fn = os.path.join(out, slug(e["title"]) + ".md")
        open(fn, "w").write(md); written.append(e["title"])
    # study hub
    topics = "\n".join(f"- **{tag}** — " + ", ".join(f"[[{t}]]" for t in titles)
                       for tag, titles in sorted(by_tag.items()))
    hub = ("---\n"
           f"title: {hub_title}\nstudy: {study}\ntype: hub\n"
           f"tags: [hub, {study.lower().replace('-','')}]\n"
           "note: informational ops support — NOT a source of record\n---\n\n"
           f"# {hub_title}\n\nGenerated index of {len(written)} operational notes ingested for "
           f"{study}. Each note links back here; notes on the same topic link to each other.\n\n"
           f"## Topics\n{topics}\n")
    open(os.path.join(out, slug(hub_title) + ".md"), "w").write(hub)
    return len(written)

DEMO_ENTRIES = [
    ("Protocol Amendment 2 distributed", "protocol", "2026-03-04", "Clin Ops",
     "Amendment 2 circulated to sites and the biostatistics team; updates the schedule of assessments and an exclusion criterion. Statistics impact reviewed against the SAP; no change to primary analysis populations."),
    ("Kickoff meeting minutes", "milestone", "2026-02-10", "Project Manager",
     "Study kickoff held. Confirmed roles, the data flow, the double-programming plan, and target dates for first data transfer and database lock. Action items assigned to DM, biostatistics, and clin-pharm."),
    ("Data transfer DTA-03 received", "data-transfer", "2026-04-22", "Data Management",
     "Scheduled lab transfer DTA-03 received from the central lab and reconciled against the transfer agreement. Format and record counts matched the specification; one minor mapping query opened and tracked."),
    ("Central lab transfer specification finalized", "data-transfer", "2026-02-28", "Data Management",
     "Transfer spec for the central lab finalized: cadence, file format, variable mapping, and reconciliation rules. Shared with the lab and biostatistics for sign-off ahead of first transfer."),
    ("Monitoring visit MV-2 report filed", "monitoring", "2026-05-09", "Medical Monitor",
     "Interim monitoring visit report filed. Source-data review and protocol-deviation log reviewed; follow-up items routed to the site. No safety signal escalation required at this visit."),
    ("Risk review — enrollment pace", "monitoring", "2026-05-15", "Project Manager",
     "Operational risk review of enrollment pace versus plan. Mitigations agreed with sites; flagged for the next governance check-in. Tracked alongside the monitoring plan."),
]

def make_demo(tmp):
    os.makedirs(tmp, exist_ok=True)
    for i, (title, tag, date, frm, body) in enumerate(DEMO_ENTRIES):
        h = (f'<!doctype html><html><head><meta charset="utf-8"><title>{title}</title>'
             f'<meta name="study" content="CP-101"><meta name="date" content="{date}">'
             f'<meta name="from" content="{frm}"><meta name="tags" content="{tag}">'
             f'</head><body><h1>{title}</h1><p>{body}</p></body></html>')
        open(os.path.join(tmp, f"entry_{i:02d}.html"), "w").write(h)
    return tmp

def main():
    ap = argparse.ArgumentParser(description="Generate a Markdown vault from Study KB entries.")
    ap.add_argument("--kb", help="folder of Study KB .html entries")
    ap.add_argument("--out", default="vault_from_kb", help="output vault folder (default: vault_from_kb)")
    ap.add_argument("--demo", action="store_true", help="synthesise sample entries and convert (runnable)")
    a = ap.parse_args()

    if a.demo:
        kb = make_demo(os.path.join(tempfile.gettempdir(), "cp101_kb_demo"))
        out = a.out if a.out != "vault_from_kb" else "vault_from_kb_demo"
        print(f"[demo] wrote {len(DEMO_ENTRIES)} sample KB entries to {kb}")
    elif a.kb:
        kb = os.path.expanduser(a.kb); out = a.out
        if not os.path.isdir(kb):
            sys.exit(f"KB folder not found: {kb}")
    else:
        ap.error("provide --kb <folder> or --demo")

    files = sorted(glob.glob(os.path.join(kb, "*.html")) + glob.glob(os.path.join(kb, "*.htm")))
    if not files:
        sys.exit(f"no .html entries in {kb}")
    entries = [parse_entry(f) for f in files]
    n = write_vault(entries, out)
    print(f"converted {len(files)} KB entries -> {n} notes + 1 hub  in  {out}/")
    print(f"open the '{out}' folder in Obsidian/Foam, or point Knowledge_Graph.html's model at it.")

if __name__ == "__main__":
    main()
