#!/usr/bin/env python3
"""
assemble_vault.py  —  Build the CP-101 Markdown knowledge vault from the
deterministic graph model + authored note bodies.

The graph is GENERATED, not hand-wired: nodes, types, owners and the link
structure all come from graph_model.json (the single source of truth that the
interactive viewer also reads). Each note is written as an Obsidian/Foam-ready
Markdown file: YAML frontmatter + body + a wikilinked "Related" section whose
[[links]] exactly match the model's edges, so the app's graph view and the
bundled viewer show the *same* graph.

Usage:
    python3 assemble_vault.py            # uses bodies.json if present
    python3 assemble_vault.py --check    # validate model + report, write nothing

Governance: this only ever writes OPERATIONS content for a synthetic study.
No PHI, no participant-level data, no unblinded codes, no reported numbers.
"""
import json, os, sys, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
VAULT = os.path.join(HERE, "vault")
UPDATED = "2026-06-25"  # stamp deterministically; real runs use the ingest date

TYPE_LABEL = {
    "hub": "study home", "design": "study design & data collection",
    "stats": "statistics & programming", "data": "data management & flow",
    "ops": "process gate", "safety": "safety & oversight",
    "supply": "randomization, blinding & drug", "program": "deliverables & timeline",
    "reference": "people, standards & vendors",
}

def fname(title):
    # Obsidian/Foam resolve [[Title]] to "Title.md"; keep filename == title.
    return title.replace("/", "-").strip() + ".md"

def yaml_list(items):
    return "[" + ", ".join(items) + "]"

def main():
    check = "--check" in sys.argv
    model = json.load(open(os.path.join(HERE, "graph_model.json")))
    nodes = model["nodes"]
    by_id = {n["id"]: n for n in nodes}
    title_of = {n["id"]: n["title"] for n in nodes}

    # validate every link resolves
    bad = [(n["id"], l) for n in nodes for l in n["links"] if l not in by_id]
    assert not bad, f"unresolved links: {bad}"

    bodies = {}
    bjson = os.path.join(HERE, "bodies.json")
    if os.path.exists(bjson):
        bodies = json.load(open(bjson))

    if check:
        deg = sorted(((n["title"], n["degree"]) for n in nodes), key=lambda x: -x[1])
        print(f"nodes={len(nodes)} edges={len(model['edges'])} "
              f"bodies={len(bodies)}/{len(nodes)}")
        print("most-connected:", deg[:5])
        missing = [n['id'] for n in nodes if n['id'] not in bodies]
        if missing:
            print("bodies pending:", missing)
        return

    os.makedirs(VAULT, exist_ok=True)
    written = 0
    for n in nodes:
        body = bodies.get(n["id"], "_(body pending — run the authoring step)_")
        # outgoing links, hub first then by type for a tidy Related block
        links = sorted(n["links"], key=lambda l: (by_id[l]["type"] != "hub", title_of[l]))
        related = "\n".join(
            f"- [[{title_of[l]}]] — *{TYPE_LABEL.get(by_id[l]['type'], by_id[l]['type'])}*"
            for l in links
        )
        fm = (
            "---\n"
            f"title: {n['title']}\n"
            f"study: {model['study']}\n"
            f"type: {n['type']}\n"
            f"status: {n['status']}\n"
            f"owner: {n['owner']}\n"
            f"updated: {UPDATED}\n"
            f"aliases: {yaml_list([n['id']])}\n"
            f"tags: {yaml_list([n['type'], model['study'].lower().replace('-', ''), 'ops-only'])}\n"
            "source: informational ops support — NOT a source of record\n"
            "---\n"
        )
        md = f"{fm}\n# {n['title']}\n\n{body.strip()}\n\n## Related\n{related}\n"
        with open(os.path.join(VAULT, fname(n["title"])), "w") as f:
            f.write(md)
        written += 1
    print(f"wrote {written} notes to {VAULT}")

if __name__ == "__main__":
    main()
