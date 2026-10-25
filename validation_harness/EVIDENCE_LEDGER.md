# Evidence Ledger: Trial-Management Validation Harness

_Generated 2026-10-24 23:49 EDT · R version 4.6.0 (2026-04-24) · 5 of 6 scan-based gates green, 1 manual record, 1 not signed · run on this repo's synthetic deliverables · human sign-off pending on every gate._

| Gate | Guards (the fragile object) | Status | Evidence (automated) | Human sign-off |
|---|---|:--:|---|---|
| **G1 Reproducibility & environment** | the sandbox's eight committed output files regenerate byte for byte from code and seed, and every R program parses | green | 469 R programs parse (0 fail); the synthetic study regenerates 8 of 8 committed ADaM-shaped files (adsl, adex, adpc, adpp, adae, advs, adlb, adeg) byte for byte from seed 2026 (base R) | ☐ pending |
| **G2 PK and count convention scans** | PK programs use log-scale geometric statistics, counts use distinct participants, and the drafter's number check has a self-test (pattern scans; they do not show where a reported number comes from) | green | static scans: geometric-on-log-scale in 14 PK programs; distinct-participant counting in 162 programs; drafter number-validation self-test present (5) | ☐ pending |
| **G3 Data structure & integrity** | the analysis data passes the custom structural checks (not Pinnacle 21 or CDISC CORE), is intact, and PHI-free | green | custom structural checks PASS (checks/conformance.R; not Pinnacle 21 or CDISC CORE); 0 trial-sense 'subject' in programs; 0 PHI/PII hits in deliverable data/docs (raw public-registry calibration corpus excluded) | ☐ pending |
| **G4 SAS/R twin structural parity** | the SAS and R twins line up program for program (structure only) | green | 217 SAS / 217 R twin programs; 0 twin TLF-number mismatches; 0 within-design number collisions; all R parse. Structural only: SAS is not executed (no license), so no outputs are compared, and the R twins were written to mirror the SAS | ☐ pending |
| **G5 Adversarial QC panel** | no skeptical reader can break the deliverable | manual | manual record, not computed here: an AI-agent review panel reported 51 P0/P1 parity findings resolved; 6 previously-pending twin pairs re-verified by the panel (5 confirmed, 1 sad/t_lab_marked_abnormal denominator gap found and fixed). Human review of these findings is not yet recorded | ☐ pending |
| **G6 Reporting conventions** | TLF numbering, scope and ICH E14 conventions hold (pattern checks, not a regulatory review) | red | 0 TLF-number collisions; 0 out-of-scope eDISH/Hy's terms in programs; ICH E14 categorical thresholds (>450/480/500 ms, change >30/60 ms) in 10/10 QTc tables; QTc change figures: 4/10 draw the +10 ms mean-effect line and 6/10 draw 30/60 ms lines (one convention must apply to all) | ☐ pending |
| **G7 AI-governance documentation present** | the drafter's AI-use limits (frozen model, human gate) are written down and no PHI turns up (file scans); accountability needs a named statistician's signature, not yet given | not signed | 0 experimental/non-standard method labels in analysis programs; 0 PHI hits; frozen-model + human-gate discipline documented in 7 tlf_interpret files. Not signed: the scans pass, but no one has signed for AI use | ☐ pending |
| **G8 Package & GUI consistency** | the package is navigable, linked, and internally consistent | green | package_qc.py: 0 issues across 41 HTML pages, the Markdown files and the text of the published spreadsheets, Word files, decks, PDFs and JSON (broken links, retired content, missing or orphaned pages, terminology, framing and count drift) | ☐ pending |

> **The split:** every evidence cell above is produced by this script except G5, which is a
> manual record. G7's scans pass, but its status stays "not signed" until a named statistician
> signs for AI use. Most checks are structural; SAS is never executed. The **Human sign-off** column
> is not automated: a named biostatistician reviews each gate and signs, and no gate is signed yet.
> Re-run: `bash validation_harness/run_harness.sh`
