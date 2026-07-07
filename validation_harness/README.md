# The Trial‑Management Validation Harness

*A reusable, field‑general procedure for being confident in a clinical‑biometrics deliverable —
an analysis dataset, a table/listing/figure, a monitoring output — before it is used to inform a
decision or ships to a sponsor. Eight named gates, explicit pass criteria, and a fixed evidence
ledger. The organizing principle throughout: **automate detection and re‑execution; reserve the
final decision for the qualified biostatistician.***

This is the trial‑management sibling of a general **pre‑submission validation harness** for
computational research — the same rigor apparatus, ported to a new domain. A deliverable is
"delivery‑confident" when every applicable gate is green with a signed artifact behind it.

The checks in [`run_harness.sh`](run_harness.sh) are **runnable and dogfooded**: they execute against
this repository's own SAS/R TLF pseudocode libraries and synthetic ADaM data and emit
[`EVIDENCE_LEDGER.md`](EVIDENCE_LEDGER.md) (one row per gate). Open [`index.html`](index.html) for the
ledger view.

> Scope note: everything here operates on **100% synthetic** data. There is no PHI. The gates are the
> *procedure*; the numbers they check are demonstrative.

---

## The eight gates

### G1 — Reproducibility & environment gate
**Claim it defends:** *"Any qualified programmer can regenerate every dataset, table, listing, and figure from the code and the frozen inputs."*

- **Do:** version‑controlled programs; scripted (never manual) derivations; a pinned tool stack (SAS version, R + pharmaverse package versions, Phoenix WinNonlin build, Pinnacle 21 version) captured in a lockfile; a **frozen, dated, hash‑stamped input extract**; a **clean‑room re‑run** from a fresh checkout under a service account (not a working directory); a **program‑to‑output map** linking each TLF number to the program and output that produced it.
- **Automatable:** environment capture; clean‑clone re‑execution; output‑invariance across repeated runs; "every program parses / compiles."
- **Human judgment:** define the numerical tolerance up front (bit‑identical is not guaranteed across SAS/R/BLAS builds); sign the run.
- **Pass criterion:** a fresh clone reproduces the synthetic study **bit‑stable from its seed**; **every** program parses; no machine‑specific paths.

### G2 — Numeric‑provenance gate (numbers ↔ validated tool)
**Claim it defends:** *"Every reported or regulated number came from a validated tool — never a language model — and summary/simulation numbers carry their uncertainty."*

- **Do:** every PK parameter from **Phoenix WinNonlin** (NCA); every CDISC conformance finding from **Pinnacle 21**; every reported count/mean from the validated pipeline; **AI drafts the words *around* a number, never the number.** Geometric PK statistics computed **on the log scale** (`exp(mean(log(x)))`, never `exp(mean(x))`); safety/disposition counts are **distinct participants**, not records. For the synthetic simulation, a Monte‑Carlo stability check (seed‑invariance; MCSE analog).
- **Automatable:** table‑vs‑source numeric diff; a scan that every PK program uses the log‑scale geometric convention; a scan that counts use `n_distinct(USUBJID)` / `CLASS USUBJID`; confirmation that the narrative drafter's self‑test **rejects any number it did not receive from the pipeline**.
- **Human judgment:** whether a difference sits within Monte‑Carlo noise (a 1–2 MCSE move is not a finding).
- **Pass criterion:** zero LLM‑sourced numbers; the log‑scale geometric convention present in every PK mean program; counts distinct‑participant; the drafter's number‑validation self‑test is present.

### G3 — Data conformance & integrity gate (CDISC + no PHI)
**Claim it defends:** *"The analysis data is CDISC‑conformant, referentially intact across domains, correctly termed, and carries no PHI/PII or unblinded content."*

- **Do:** ADaM IG conformance (required variables, controlled terminology, valid `PARAMCD`, key structure); **cross‑domain referential integrity** (`USUBJID` keys align; ADPP ⊆ ADSL; AE treatment attribution is valid for the design); **"participant," not "subject"** in prose with CDISC `USUBJID`/`SUBJID` preserved exactly; **no PHI/PII, participant‑level, or unblinded data** in any shared/AI artifact.
- **Automatable:** Pinnacle 21‑style conformance; key‑integrity joins; terminology scan; PHI/PII (names/emails/phones) scan.
- **Human judgment:** adjudicate a genuine conformance finding vs a tolerable convention.
- **Pass criterion:** required variables present in every domain; `USUBJID` referential integrity holds; `PARAMCD` well‑formed (no malformed codes); crossover `TRT01A` tracks `TRTSEQ`; zero trial‑sense "subject"; zero PHI/PII.

### G4 — Double‑programming parity gate (SAS ↔ R)
**Claim it defends:** *"Key outputs are independently double‑programmed and reconciled — the two implementations compute the identical result."*

- **Do:** independent **SAS and R** implementations of each TLF; reconcile **population, denominator, statistic, row/column set, and reference lines**; keep a parity ledger of every resolved discrepancy.
- **Automatable:** twin inventory parity (matching stems); twin **TLF‑number consistency**; per‑stem parity checks; "every program parses."
- **Human judgment:** when the twins diverge, decide **which side is correct** against the SAP convention.
- **Pass criterion:** the SAS and R libraries have matching stems; every twin shares its TLF number (zero mismatches); zero within‑design number collisions; all R parses; every parity discrepancy resolved or dispositioned.

### G5 — Adversarial QC panel gate
**Claim it defends:** *"Independent skeptical reviewers, from several angles, cannot break the deliverable — and what did not reconcile is reported honestly, not buried."*

- **Do:** a **multi‑lens QC panel** per deliverable (correctness · parity · conformance · terminology · scope), with **adversarial verification** — each finding re‑checked by an independent reviewer instructed to *refute* it, keeping only survivors — plus **honest‑negative reporting**: open items are surfaced, not hidden. A named human reviewer signs.
- **Automatable:** the panel and its refutation votes.
- **Human judgment (mandatory):** adjudicate each surviving finding; the sign‑off. Automated reviewers *augment, never replace* the reviewer — treat panel output as leads to verify, not verdicts.
- **Pass criterion:** every surviving high finding is resolved or explicitly rebutted with evidence; open items are disclosed in the ledger.

### G6 — Regulatory & reporting‑standard gate
**Claim it defends:** *"The deliverables meet the field's regulatory and reporting standards, in the expected structure."*

- **Do:** conform to **CDISC ADaM IG** (analysis datasets), **ICH E3** (CSR TLF structure), **ICH E9** (analysis populations), **ICH E14** (QTc categorical / mean‑change conventions), and **21 CFR Part 11 / ALCOA++** (audit trail, e‑records). **TLF numbering integrity** (unique, twin‑consistent, per the study shells/index). **Scope compliance** — e.g. this library deliberately carries **no eDISH / Hy's‑Law terminology**; a neutral liver‑safety scatter stands in its place.
- **Automatable:** numbering‑collision check; scope/terminology compliance; presence checks per deliverable type against the applicable checklist.
- **Human judgment:** the narrative adequacy of each required item.
- **Pass criterion:** zero TLF‑number collisions; zero out‑of‑scope terminology; ICH E14 QTc conventions applied uniformly; numbering twin‑consistent.

### G7 — AI‑use governance & accountability gate
**Claim it defends:** *"AI assistance is disclosed and bounded: validated tools own every number, a qualified human signs every output, only operations content touches any shared/AI tool, models used for anything regulated are frozen, and there is a full audit trail."*

- **Do:** **validated tools own every number** (G2 feeds in); AI drafts and checks — a **named biostatistician signs and is accountable**; **operations‑only** — no PHI, participant‑level, or unblinded data in any AI/shared tool; an **on‑prem / frozen model** (pinned tag + quantization + digest + temperature 0) for anything that informs a regulated decision, with a Part‑11 record; **no experimental or non‑standard research methods** in production materials.
- **Automatable:** forbidden‑content scan; PHI scan; confirmation that the frozen‑model discipline and a human gate are documented in every AI pipeline.
- **Human judgment:** the disclosure, the sign‑off, the accountability — essentially all of it.
- **Pass criterion:** zero forbidden content; zero PHI; every AI pipeline has a documented human gate; the frozen‑model discipline is documented; the AI‑use disclosure is accurate.

---

## What a machine can do vs what only the biostatistician can do

- **Automatable (let the harness run these):** clean‑clone re‑execution and output‑invariance; program parse/compile; table‑vs‑source numeric diffs and the geometric‑convention scan; ADaM conformance and cross‑domain key integrity; the SAS↔R parity and numbering checks; the terminology, PHI, scope, and forbidden‑content scans; the QC panel and its refutation votes.
- **Human‑judgment gates (never delegate the final call):** which twin is correct when they diverge; whether a difference is Monte‑Carlo noise; adjudicating each conformance and QC finding; the analysis‑population and reporting‑adequacy decisions; and the **sign‑off**, disclosure, and accountability. A deliverable is not delivered on a tool's say‑so.

## The evidence ledger

A single table, committed with the deliverable, **one row per gate**: *gate · applies? (Y/N) · status
(green/red) · artifact (path to the script/log/output that proves it) · human sign‑off · date.* The
deliverable is delivery‑confident when every "applies = Y" row is green with an artifact behind it.
Run [`run_harness.sh`](run_harness.sh) to (re)generate [`EVIDENCE_LEDGER.md`](EVIDENCE_LEDGER.md) and
`ledger.json` against this repo.

## Standards referenced

CDISC ADaM Implementation Guide · ICH E3 (CSR) · ICH E6 (GCP) · ICH E9 (statistical principles) ·
ICH E14 (QT/QTc) · CDISC controlled terminology · 21 CFR Part 11 / ALCOA++ · GAMP‑5 (computerized
system validation) · EQUATOR‑style reporting discipline. Method lineage: the pre‑submission
validation harness for computational research (reproducibility · numeric‑provenance · integrity ·
robustness · adversarial review · reporting standard · AI‑use), re‑expressed for trial deliverables.
