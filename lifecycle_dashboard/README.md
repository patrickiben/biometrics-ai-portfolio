# Study Lifecycle Monitor

A self-contained, offline dashboard for **biostatisticians to monitor study lifecycles** —
protocol → CSR — at the *operational* level. Open [`Study_Lifecycle_Monitor.html`](Study_Lifecycle_Monitor.html)
in any browser; no server, no dependencies, no network.

This is the **operational/program** complement to the participant-safety monitoring dashboard
(TRIALMON): it watches **deliverables, data readiness, TLF production, and milestones**, not
participant-level clinical signals.

## What it shows
- **KPI strip** — active studies, at-risk / on-watch counts, portfolio open queries, avg deliverables
  complete, TLFs finalized, next DB-lock countdown.
- **Portfolio health heatmap** — every study × {Timeline, Data, TLF, Resource} RAG; click a cell to drill in.
- **Operational early-warning signals** — ranked, e.g. "DB lock at risk: N queries with lock in D days",
  "TLF production behind", "double-programming lag", "milestone overdue".
- **Milestone track** — Protocol → SAP → FPFV → LPLV → DBL → TLFs → CSR, with done / in-progress / overdue.
- **Data readiness** — clean %, SDV %, open-query sparkline, days-to-DBL.
- **TLF production funnel** — Planned → Programmed → QC-passed → Finalized.
- **Deliverables pipeline** — done/total by phase (echoes the Protocol→CSR deliverables register).
- **Sortable roster** + per-study detail modal.

## The data is SIMULATED
A seeded, reproducible synthetic portfolio of 8 studies across all four phases — **not real study
data**. Each panel notes where the live value would come from (the modal's "Where these numbers would
come from"): milestones → **CTMS**; enrollment/queries/clean/SDV → **EDC**; the TLF funnel → the **TLF
program tracker**; deliverables → the **deliverables register**. Wire each read-only.

## How the risk score works (transparent — no black box)
Each dimension is a plain weighted 0–100 score, scaled by how close the relevant gate is (days-to-DBL,
reporting proximity): Timeline = overdue milestones + DBL pressure; Data = query backlog + (1−clean) +
(1−SDV), weighted by DBL proximity; TLF = (1−finalized/planned) weighted by reporting proximity;
Resource = double-programming lag + open discrepancies. Overall = weighted average. Green <33, Watch
33–66, At risk >66. The formula is shown in the dashboard itself.

## Deliberately excluded
- **No experimental components** (no research-WIP engine of any kind).
- **No non-standard or manuscript-specific analytic methods**: just standard, defensible operational monitoring.
- **Operational only**: no PHI, no participant-level data, no reported clinical numbers. Reported/regulated
  values always come from validated tools.

## Notes
Verified: embedded JS passes `node --check`; the data/scoring runs headless with no NaN and a full
green/amber/red spread. Edit the seed (`rng(20260621)`) or the `genStudy` ranges to reshape the demo
portfolio; replace the generator with a read-only pull from CTMS/EDC/your trackers to go live.
