# The Trial‑Management Validation Harness

*A reusable, field‑general procedure for being confident in a clinical‑biometrics deliverable
(an analysis dataset, a table/listing/figure, a monitoring output) before it is used to inform a
decision or ships to a sponsor. Eight named gates, explicit pass criteria, and a fixed evidence
ledger. The organizing principle throughout: **automate detection and re‑execution; reserve the
final decision for the qualified biostatistician.***

This is the trial‑management sibling of a general **pre‑submission validation harness** for
computational research: the same rigor apparatus, ported to a new domain. A deliverable is
"delivery‑confident" when every applicable gate is green with a signed artifact behind it.

The checks in [`run_harness.sh`](run_harness.sh) run against this repository's own SAS/R TLF
pseudocode libraries and synthetic ADaM data and emit [`EVIDENCE_LEDGER.md`](EVIDENCE_LEDGER.md)
(one row per gate). **What is actually checked:** most checks are structural (file inventories,
pattern scans, counts); G1 re-runs the synthetic study; G5 is a manual record that the script does
not compute; G6 is currently red (the QTc change figures use two reference-line conventions); G7
reports "not signed" until a named statistician signs for AI use; SAS is never executed (no
license). No gate has a human sign-off yet. Open [`index.html`](index.html) for the
ledger view.

> Scope note: everything here operates on **100% synthetic** data. There is no PHI. The gates are the
> *procedure*; the numbers they check are demonstrative.

---

## The eight gates

### G1: Reproducibility & environment gate
**Claim it defends:** *"Any qualified programmer can regenerate every dataset, table, listing, and figure from the code and the frozen inputs."*

- **Do:** version‑controlled programs; scripted (never manual) derivations; a pinned tool stack (SAS version, R + pharmaverse package versions, Phoenix WinNonlin build, Pinnacle 21 version) captured in a lockfile; a **frozen, dated, hash‑stamped input extract**; a **clean‑room re‑run** from a fresh checkout under a service account (not a working directory); a **program‑to‑output map** linking each TLF number to the program and output that produced it.
- **Automatable:** environment capture; clean‑clone re‑execution; output‑invariance across repeated runs; "every program parses / compiles."
- **Human judgment:** define the numerical tolerance up front (bit‑identical is not guaranteed across SAS/R/BLAS builds); sign the run.
- **Pass criterion:** a fresh clone reproduces the synthetic study **bit‑stable from its seed**; **every** program parses; no machine‑specific paths.
- **As implemented here:** re-runs `simulate_study()` with seed 2026 and compares all eight committed output files (adsl, adex, adpc, adpp, adae, advs, adlb, adeg) byte for byte, and parses every R program. It does not run the TLF libraries on data or execute SAS.

### G2: Numeric‑provenance gate (numbers ↔ validated tool)
**Claim it defends:** *"Every reported or regulated number came from a validated tool, never a language model, and summary/simulation numbers carry their uncertainty."*

- **Do:** every PK parameter from a validated NCA system (**Phoenix WinNonlin**, version per the ADRG, currently 8.8, or PKNCA); every CDISC conformance finding from **Pinnacle 21**; every reported count/mean from the validated pipeline; **AI drafts the words *around* a number, never the number.** Geometric PK statistics computed **on the log scale** (`exp(mean(log(x)))`, never `exp(mean(x))`); safety/disposition counts are **distinct participants**, not records. For the synthetic simulation, a Monte‑Carlo stability check (seed‑invariance; MCSE analog).
- **Automatable:** table‑vs‑source numeric diff; a scan that every PK program uses the log‑scale geometric convention; a scan that counts use `n_distinct(USUBJID)` / `CLASS USUBJID`; confirmation that the narrative drafter's self‑test **rejects any number it did not receive from the pipeline**.
- **Human judgment:** whether a difference sits within Monte‑Carlo noise (a 1–2 MCSE move is not a finding).
- **Pass criterion:** zero LLM‑sourced numbers; the log‑scale geometric convention present in every PK mean program; counts distinct‑participant; the drafter's number‑validation self‑test is present.
- **As implemented here:** the ledger calls this gate "PK and count convention scans" because that is all it checks: log-scale geometric statistics in the PK programs, distinct-participant counting, and the presence of the drafter's self-test. Pattern scans cannot show where a reported number comes from; that takes the study's validated programs and a reviewer.

### G3: Data conformance & integrity gate (CDISC + no PHI)
**Claim it defends:** *"The analysis data is CDISC‑conformant, referentially intact across domains, correctly termed, and carries no PHI/PII or unblinded content."*

- **Do:** ADaM IG conformance (required variables, controlled terminology, valid `PARAMCD`, key structure); **cross‑domain referential integrity** (`USUBJID` keys align; ADPP ⊆ ADSL; AE treatment attribution is valid for the design); **"participant," not "subject"** in prose with CDISC `USUBJID`/`SUBJID` preserved exactly; **no PHI/PII, participant‑level, or unblinded data** in any shared/AI artifact.
- **Automatable:** Pinnacle 21‑style conformance; key‑integrity joins; terminology scan; PHI/PII (names/emails/phones) scan.
- **Human judgment:** adjudicate a genuine conformance finding vs a tolerable convention.
- **Pass criterion:** required variables present in every domain; `USUBJID` referential integrity holds; `PARAMCD` well‑formed (no malformed codes); crossover `TRT01A` tracks `TRTSEQ`; zero trial‑sense "subject"; zero PHI/PII.
- **As implemented here:** `checks/conformance.R` runs custom structural checks; it is not Pinnacle 21 or CDISC CORE. In a submission, conformance is checked with Pinnacle 21 (FDA engine 2304.3); CDISC CORE (v0.17.1, open source) is a useful cross-check but is not FDA's validator.

### G4: Double‑programming parity gate (SAS ↔ R)
**Claim it defends:** *"Key outputs are independently double‑programmed and reconciled: the two implementations compute the identical result."*

- **Do:** independent **SAS and R** implementations of each TLF; reconcile **population, denominator, statistic, row/column set, and reference lines**; keep a parity ledger of every resolved discrepancy.
- **Automatable:** twin inventory parity (matching stems); twin **TLF‑number consistency**; per‑stem parity checks; "every program parses."
- **Human judgment:** when the twins diverge, decide **which side is correct** against the SAP convention.
- **Pass criterion:** the SAS and R libraries have matching stems; every twin shares its TLF number (zero mismatches); zero within‑design number collisions; all R parses; every parity discrepancy resolved or dispositioned.
- **As implemented here:** structural parity only (matching stems and TLF numbers). SAS is not executed (no license), so no outputs are compared, and the R twins were written to mirror the SAS, so they are not independent implementations.

### G5: Adversarial QC panel gate
**Claim it defends:** *"Independent skeptical reviewers, from several angles, cannot break the deliverable, and what did not reconcile is reported honestly, not buried."*

- **Do:** a **multi‑lens QC panel** per deliverable (correctness · parity · conformance · terminology · scope), with **adversarial verification** (each finding re‑checked by an independent reviewer instructed to *refute* it, keeping only survivors) plus **honest‑negative reporting**: open items are surfaced, not hidden. A named human reviewer signs.
- **Automatable:** the panel and its refutation votes.
- **Human judgment (mandatory):** adjudicate each surviving finding; the sign‑off. Automated reviewers *augment, never replace* the reviewer: treat panel output as leads to verify, not verdicts.
- **Pass criterion:** every surviving high finding is resolved or explicitly rebutted with evidence; open items are disclosed in the ledger.
- **As implemented here:** a manual record of an AI-agent review panel. The script does not compute it (its status is "manual"), and human review of the findings is not yet recorded.

### G6: Regulatory & reporting‑standard gate
**Claim it defends:** *"The deliverables meet the field's regulatory and reporting standards, in the expected structure."*

- **Do:** conform to **CDISC ADaM IG** (analysis datasets), **ICH E3** (CSR TLF structure), **ICH E9(R1)** (analysis populations, estimands), **ICH E14** (QTc categorical / mean‑change conventions), and systems designed to meet **21 CFR Part 11** with **ALCOA++** records (audit trail, e‑records). **TLF numbering integrity** (unique, twin‑consistent, per the study shells/index). **Scope compliance**, e.g. this library deliberately carries **no eDISH / Hy's‑Law terminology**; a neutral liver‑safety scatter stands in its place.
- **Automatable:** numbering‑collision check; scope/terminology compliance; presence checks per deliverable type against the applicable checklist.
- **Human judgment:** the narrative adequacy of each required item.
- **Pass criterion:** zero TLF‑number collisions; zero out‑of‑scope terminology; ICH E14 QTc conventions applied uniformly; numbering twin‑consistent.
- **As implemented here:** pattern checks for numbering, scope terms and ICH E14 conventions (categorical >450/480/500 ms and change >30/60 ms in every QTc table; the +10 ms reference line on every QTc change figure). Not a regulatory review.

### G7: AI‑use governance & accountability gate
**Claim it defends:** *"AI assistance is disclosed and bounded: validated tools own every number, a qualified human signs every output, only operations content touches any shared/AI tool, models used for anything regulated are frozen, and there is a full audit trail."*

- **Do:** **validated tools own every number** (G2 feeds in); AI drafts and checks; a **named biostatistician signs and is accountable**; **operations‑only**, no PHI, participant‑level, or unblinded data in any AI/shared tool; an **on‑prem / frozen model** (pinned tag + quantization + digest + temperature 0) for anything that informs a regulated decision, with a Part‑11 record; **no experimental or non‑standard research methods** in production materials.
- **Automatable:** forbidden‑content scan; PHI scan; confirmation that the frozen‑model discipline and a human gate are documented in every AI pipeline.
- **Human judgment:** the disclosure, the sign‑off, the accountability; essentially all of it.
- **Pass criterion:** zero forbidden content; zero PHI; every AI pipeline has a documented human gate; the frozen‑model discipline is documented; the AI‑use disclosure is accurate.
- **As implemented here:** the ledger calls this gate "AI-governance documentation present": file scans for forbidden method labels and PHI, and for the frozen-model and human-gate rules in `tlf_interpret`. Because the gate guards accountability, its status is "not signed" (never green) until a named statistician signs for AI use; failed scans turn it red.

### G8: Package & GUI consistency gate
**Claim it defends:** *"The published package is navigable, its links resolve, and its pages and documents say the same thing."*

- **Do:** link integrity across pages and Markdown; retired content stays retired; every module is listed in the inventory; consistent terminology, framing and counts, including the text of published spreadsheets, Word files, slide decks, PDFs and JSON files.
- **Automatable:** all of the above (`package_qc.py`).
- **Human judgment:** whether the content is right; the check reads the package, not the statistics.
- **Pass criterion:** `package_qc.py` reports zero issues.
- **As implemented here:** runs `python3 package_qc.py`; external links are requested only with `--external`, so the gate does not depend on the network.

---

## What a machine can do vs what only the biostatistician can do

- **Automatable (let the harness run these):** clean‑clone re‑execution and output‑invariance; program parse/compile; table‑vs‑source numeric diffs and the geometric‑convention scan; ADaM conformance and cross‑domain key integrity; the SAS↔R parity and numbering checks; the terminology, PHI, scope, and forbidden‑content scans; the QC panel and its refutation votes.
- **Human‑judgment gates (never delegate the final call):** which twin is correct when they diverge; whether a difference is Monte‑Carlo noise; adjudicating each conformance and QC finding; the analysis‑population and reporting‑adequacy decisions; and the **sign‑off**, disclosure, and accountability. A deliverable is not delivered on a tool's say‑so.

## The evidence ledger

A single table, committed with the deliverable, **one row per gate**: *gate · applies? (Y/N) · status
(green/red; "manual" for a hand-entered record; "not signed" where only a signature can pass the gate) · artifact (path to the script/log/output that proves it) · human sign‑off · date.* The
deliverable is delivery‑confident when every "applies = Y" row is green with an artifact behind it.
Run [`run_harness.sh`](run_harness.sh) to (re)generate [`EVIDENCE_LEDGER.md`](EVIDENCE_LEDGER.md) and
`ledger.json` against this repo.

## Standards referenced

CDISC ADaM v2.1 / ADaMIG v1.3 and SDTMIG v3.4 (FDA-required; Data Standards Catalog v11.0) ·
Define-XML v2.1 · CDISC controlled terminology · ICH E3 (CSR) · ICH E6(R3) (Step 4 6 Jan 2025; EU
effective 23 Jul 2025; FDA final guidance Sep 2025); Annex 2 Step 4 3 Jun 2026 (CHMP 25 Jun 2026, EU
effective 15 Jan 2027; FDA: draft guidance Dec 2024, not final) · ICH E9(R1) (adopted 20 Nov 2019;
FDA final guidance May 2021) · ICH E14 (May 2005), E14 Q&A (R3) (10 Dec 2015) and E14/S7B Q&As
(Step 4 21 Feb 2022) · ICH M11 (Step 4 19 Nov 2025; FDA final guidance May 2026) · 21 CFR Part 11
(systems designed to meet it) / ALCOA++ · GAMP 5 (computerized system validation) · EQUATOR‑style
reporting discipline. Method lineage: the pre‑submission
validation harness for computational research (reproducibility · numeric‑provenance · integrity ·
robustness · adversarial review · reporting standard · AI‑use), re‑expressed for trial deliverables.
