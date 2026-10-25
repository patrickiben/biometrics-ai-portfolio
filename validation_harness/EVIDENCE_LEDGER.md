# Evidence Ledger: Trial-Management Validation Harness

_Generated 2026-10-24 22:11 EDT · R version 4.6.0 (2026-04-24) · 6 of 7 automated gates green, 1 manual record · run on this repo's synthetic deliverables · human sign-off pending on every gate._

| Gate | Guards (the fragile object) | Status | Evidence (automated) | Human sign-off |
|---|---|:--:|---|---|
| **G1 Reproducibility & environment** | every number is regenerable from code + frozen inputs | green | 469 R programs parse (0 fail); synthetic study re-runs bit-STABLE from seed 2026 (base R) | ☐ pending |
| **G2 Numeric-provenance** | no reported number is produced by an LLM | green | static scans: geometric-on-log-scale in 14 PK programs; distinct-participant counting in 162 programs; drafter number-validation self-test present (5) | ☐ pending |
| **G3 Data structure & integrity** | the analysis data passes the custom structural checks (not Pinnacle 21 or CDISC CORE), is intact, and PHI-free | green | custom structural checks PASS (checks/conformance.R; not Pinnacle 21 or CDISC CORE); 0 trial-sense 'subject' in programs; 0 PHI/PII hits in deliverable data/docs (raw public-registry calibration corpus excluded) | ☐ pending |
| **G4 SAS/R twin structural parity** | the SAS and R twins line up program for program (structure only) | green | 217 SAS / 217 R twin programs; 0 twin TLF-number mismatches; 0 within-design number collisions; all R parse. Structural only: SAS is not executed (no license), so no outputs are compared, and the R twins were written to mirror the SAS | ☐ pending |
| **G5 Adversarial QC panel** | no skeptical reader can break the deliverable | manual | manual record, not computed here: an AI-agent review panel reported 51 P0/P1 parity findings resolved; 6 previously-pending twin pairs re-verified by the panel (5 confirmed, 1 sad/t_lab_marked_abnormal denominator gap found and fixed). Human review of these findings is not yet recorded | ☐ pending |
| **G6 Reporting conventions** | TLF numbering, scope and ICH E14 conventions hold (pattern checks, not a regulatory review) | red | 0 TLF-number collisions; 0 out-of-scope eDISH/Hy's terms in programs; ICH E14 categorical thresholds (>450/480/500 ms, change >30/60 ms) in 10/10 QTc tables; QTc change figures: 4/10 draw the +10 ms mean-effect line and 6/10 draw 30/60 ms lines (one convention must apply to all) | ☐ pending |
| **G7 AI-use governance & accountability** | AI is disclosed and bounded; a human signs | green | 0 experimental/non-standard method labels in analysis programs; 0 PHI hits; frozen-model + human-gate discipline documented in 7 tlf_interpret files | ☐ pending |
| **G8 Package & GUI consistency** | the package is navigable, linked, and internally consistent | green | package_qc.py: 0 issues across 41 HTML pages (broken links, deliverables missing from the nav, orphaned pages, terminology drift, count drift) | ☐ pending |

> **The split:** every evidence cell above is produced by this script except G5, which is a
> manual record. Most checks are structural; SAS is never executed. The **Human sign-off** column
> is not automated: a named biostatistician reviews each gate and signs, and no gate is signed yet.
> Re-run: `bash validation_harness/run_harness.sh`
