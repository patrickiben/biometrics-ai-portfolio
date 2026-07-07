# Evidence Ledger — Trial-Management Validation Harness

_Generated 2026-07-07 10:19 EDT · R version 4.6.0 (2026-04-24) · 8/8 gates green · dogfooded on this repo's synthetic deliverables._

| Gate | Guards (the fragile object) | Status | Evidence (automated) | Human sign-off |
|---|---|:--:|---|---|
| **G1 Reproducibility & environment** | every number is regenerable from code + frozen inputs | 🟢 green | 453 R programs parse (0 fail); synthetic study re-runs bit-STABLE from seed 2026 (base R) | ☐ pending |
| **G2 Numeric-provenance** | no reported number is produced by an LLM | 🟢 green | geometric-on-log-scale in 14 PK programs; distinct-participant counting in 162 programs; drafter number-validation self-test present (5) | ☐ pending |
| **G3 Data conformance & integrity** | the analysis data is CDISC-conformant, intact, and PHI-free | 🟢 green | ADaM conformance PASS (checks/conformance.R); 0 trial-sense 'subject' in programs; 0 PHI/PII hits in deliverable data/docs (raw public-registry calibration corpus excluded) | ☐ pending |
| **G4 Double-programming parity (SAS<->R)** | the two independent implementations agree | 🟢 green | 217 SAS / 217 R twin programs; 0 twin TLF-number mismatches; 0 within-design number collisions; all R parse | ☐ pending |
| **G5 Adversarial QC panel** | no skeptical reader can break the deliverable | 🟢 green | multi-lens fix->adversarial-verify panel applied; 51 P0/P1 parity findings resolved; 6 previously-pending twin-pairs independently re-verified (5 confirmed, 1 sad/t_lab_marked_abnormal denominator gap found + fixed); no open items | ☐ pending |
| **G6 Regulatory & reporting standard** | CDISC/ICH/Part-11 structure is met | 🟢 green | 0 TLF-number collisions; 0 out-of-scope eDISH/Hy's terms in programs; ICH E14 QTc reference lines in 5 QTc figures | ☐ pending |
| **G7 AI-use governance & accountability** | AI is disclosed and bounded; a human signs | 🟢 green | 0 experimental/non-standard method labels in analysis programs; 0 PHI hits; frozen-model + human-gate discipline documented in 24 wiki pages | ☐ pending |
| **G8 Package & GUI consistency** | the package is navigable, linked, and internally consistent | 🟢 green | package_qc.py: 0 issues across 39 HTML pages (broken links, deliverables missing from the nav, orphaned pages, terminology drift, count drift) | ☐ pending |

> **The split:** every cell above is machine-produced. The **Human sign-off** column is not — a
> named biostatistician reviews each green gate and signs. A deliverable is delivery-confident
> when every applicable gate is green **and** signed. Re-run: `bash validation_harness/run_harness.sh`
