# Knowledge Vault for Study Operations  ·  *proposed capability*

A local-first **Markdown vault** (the idea behind Obsidian / Foam / Logseq) that turns the
Study Knowledge Base into a **navigable, linked graph** of a study's operational knowledge —
and a clean corpus the on-prem model can read. Demonstrated on a synthetic study, **CP-101**.

> **Governance (unchanged):** operations only — never PHI, participant-level, or unblinded data.
> Reported numbers come from validated tools; the vault is *informational ops support, **not** a
> source of record*. This is a **proposed** capability, pending management approval — not current practice.

## Start here
| File | What it is |
|------|------------|
| **`Knowledge_Vault_Design.html`** | The design note — what it is, how it wires into the Study KB + local SLM, governance, and which tool to pick. **Open this first.** |
| **`Knowledge_Graph.html`** | The self-contained interactive graph (no install). Hover to focus a note, click for the note + backlinks, search, toggle note types. |
| **`vault/`** | The 28 real `.md` notes. Open this folder *as a vault* in Obsidian or Foam — its graph view matches the bundled one. |

## How it's built (generated, not hand-drawn)
```
graph_model.json      ← single source of truth (28 nodes, 59 edges, 8 clusters)
   │  assemble_vault.py        → writes vault/*.md   (frontmatter + body + [[wikilinks]])
   │  (build_viewer data)      → Knowledge_Graph.html embeds the same model
   └─ kb_to_vault.py           → the PRODUCTION path: live Study KB entries → a generated vault
```

| Script | Does |
|--------|------|
| `python3 assemble_vault.py` | Rebuild the 28 curated notes from `graph_model.json` + `bodies.json`. |
| `python3 assemble_vault.py --check` | Validate the model + report (writes nothing). |
| `python3 kb_to_vault.py --demo` | Synthesise sample Study KB entries and convert them → `vault_from_kb_demo/` (runnable out of the box). |
| `python3 kb_to_vault.py --kb "~/Study Knowledge Base" --out vault_from_kb` | Convert **live** Study KB `.html` entries into a vault + study hub, with hub + topic cross-links. |

## Files
- `Knowledge_Vault_Design.html` — design note (start here)
- `Knowledge_Graph.html` — interactive viewer (self-contained)
- `vault/` — 28 generated Markdown notes (open in Obsidian/Foam)
- `graph_model.json` — nodes + edges (source of truth)
- `bodies.json` — authored note bodies
- `assemble_vault.py` — vault generator
- `kb_to_vault.py` — Study KB → vault converter (production path)
- `graph_preview.png` — static preview of the graph
- `design_spec.json`, `viewer_data.json`, `clusters.json` — build artifacts

## Pick a tool
- **Foam** (VS Code extension, MIT) — recommended start; lowest-friction IT path.
- **Obsidian** — best graph/UX; needs a commercial-use licence at work; vet plugins.
- **Logseq** — open-source outliner alternative.

Because the vault is just Markdown + git, **you own the files, not the app** — swap the viewer freely.
