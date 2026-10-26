# The Trial‑Management Validation Harness

*A reusable, field‑general procedure for being confident in a clinical‑biometrics deliverable
(an analysis dataset, a table/listing/figure, a monitoring output) before it is used to inform a
decision or ships to a sponsor. Ten named gates, explicit pass criteria, and a fixed evidence
ledger. The organizing principle throughout: **automate detection and re‑execution; reserve the
final decision for the qualified biostatistician.***

This is the trial‑management sibling of a general **pre‑submission validation harness** for
computational research: the same rigor apparatus, ported to a new domain. A deliverable is
"delivery‑confident" when every applicable gate is green with a signed artifact behind it.

The checks in [`run_harness.sh`](run_harness.sh) run against this repository's own SAS/R TLF
pseudocode libraries and synthetic ADaM data and emit [`EVIDENCE_LEDGER.md`](EVIDENCE_LEDGER.md)
(one row per gate). **What is actually checked:** most checks are structural (file inventories,
pattern scans, counts); G1 re-runs the synthetic study; G9 recomputes the sandbox's PK,
bioequivalence and adverse-event results with separately written code; G10 reports which planted
programming defects the other gates and the module tests catch; G5 is a manual record that the script does
not compute; G6 checks that every QTc change figure uses one reference-line convention (0, 30 and
60 ms, the ICH E14 categorical thresholds) and went green on 2026-10-25 after the two figure types that
drew a +10 ms line were aligned; G7
reports "not signed" until a named statistician signs for AI use; SAS is never executed (no
license). No gate has a human sign-off yet. Open [`index.html`](index.html) for the
ledger view.

> Scope note: everything here operates on **100% synthetic** data. There is no PHI. The gates are the
> *procedure*; the numbers they check are demonstrative.

---

## The ten gates

### G1: Reproducibility & environment gate
**Claim it defends:** *"Any qualified programmer can regenerate every dataset, table, listing, and figure from the code and the frozen inputs."*

- **Do:** version‑controlled programs; scripted (never manual) derivations; a pinned tool stack (SAS version, R + pharmaverse package versions, Phoenix WinNonlin build, Pinnacle 21 version) captured in a lockfile; a **frozen, dated, hash‑stamped input extract**; a **clean‑room re‑run** from a fresh checkout under a service account (not a working directory); a **program‑to‑output map** linking each TLF number to the program and output that produced it.
- **Automatable:** environment capture; clean‑clone re‑execution; output‑invariance across repeated runs; "every program parses / compiles."
- **Human judgment:** define the numerical tolerance up front (bit‑identical is not guaranteed across SAS/R/BLAS builds); sign the run.
- **Pass criterion:** a fresh clone reproduces the synthetic study **bit‑stable from its seed**; **every** program parses; no machine‑specific paths.
- **As implemented here:** re-runs `simulate_study()` with seed 2026, writes doubles at 12 significant digits exactly as `run_lifecycle.R` does, and compares all eight committed output files (adsl, adex, adpc, adpp, adae, advs, adlb, adeg) byte for byte, and parses every R program. It does not compare `results_summary.csv` (G9 checks it), run the TLF libraries on data or execute SAS.

### G2: Numeric‑provenance gate (numbers ↔ validated tool)
**Claim it defends:** *"Every reported or regulated number came from a validated tool, never a language model, and summary/simulation numbers carry their uncertainty."*

- **Do:** every PK parameter from a validated NCA system (**Phoenix WinNonlin**, version per the ADRG, currently 8.8, or PKNCA); every CDISC conformance finding from **Pinnacle 21**; every reported count/mean from the validated pipeline; **AI drafts the words *around* a number, never the number.** Geometric PK statistics computed **on the log scale** (`exp(mean(log(x)))`, never `exp(mean(x))`); safety/disposition counts are **distinct participants**, not records. For the synthetic simulation, a Monte‑Carlo stability check (seed‑invariance; MCSE analog).
- **Automatable:** table‑vs‑source numeric diff; a scan that every PK program uses the log‑scale geometric convention; a scan that counts use `n_distinct(USUBJID)` / `CLASS USUBJID`; confirmation that the narrative drafter's self‑test **rejects any number it did not receive from the pipeline**.
- **Human judgment:** whether a difference sits within Monte‑Carlo noise (a 1–2 MCSE move is not a finding).
- **Pass criterion:** zero LLM‑sourced numbers; the log‑scale geometric convention present in every PK mean program; counts distinct‑participant; the drafter's number‑validation self‑test is present.
- **As implemented here:** the ledger calls this gate "PK and count convention scans" because that is all it checks: log-scale geometric statistics in the PK programs, distinct-participant counting, and the presence of the drafter's self-test. Pattern scans cannot show where a reported number comes from; that takes the study's validated programs and a reviewer. Since 2026-10-26 the log-scale check runs per program (`checks/g2_geo.py`): each of the 27 PK programs in the R library must take its geometric statistics from the log scale (through `pkstats()`, whose own body must compute `exp(mean(log(x)))` and the geometric CV from `var(log(x))`, or through an explicit `log()`), may assign `geomean` only from a log-scale expression, and must have a SAS twin that uses `log()` or the `%pkstats` macro (whose body must work on the log scale). Comments do not count. Four negative controls each turn G2 red: D04's `exp(mean(x))`, a `pkstats()` helper without logs, a `%pkstats` macro without logs, and a program with no `log()` call. Before that change the scan counted files, not programs, and the registry-v2 seeded-defect run below records that it missed D04.

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
- **As implemented here:** pattern checks for numbering, scope terms and ICH E14 conventions (categorical >450/480/500 ms and change >30/60 ms in every QTc table; reference lines at 30 and 60 ms, and no +10 ms line, on every QTc change figure). The 10 ms threshold of regulatory concern applies to the upper bound of a placebo-corrected mean effect in a thorough QT study, which these descriptive change figures do not estimate. Cite ICH E14 (May 2005), E14 Q&A (R3) (10 Dec 2015) and the E14/S7B Q&As (Step 4 21 Feb 2022). Not a regulatory review.

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

### G9: Independent recomputation gate
**Claim it defends:** *"The reported numbers can be re-derived from the analysis data by code written separately from the code that produced them."*

- **Do:** recompute the NCA parameters from ADPC: AUC(0-t) by the linear trapezoid from t = 0 (the predose zero kept) to the last quantifiable concentration, BLQ as 0 (ICH M13A); Cmax and Tmax; lambda_z by log-linear least squares on the last three positive points; AUC(0-inf) = AUC(0-t) + Clast/lambda_z, t1/2, CL/F and Vz/F. Recompute the 2x2 bioequivalence result in closed form (d_i = log Y in period 1 minus log Y in period 2; log GMR = (mean d_TR - mean d_RT)/2; SE = 0.5 s_p sqrt(1/n_TR + 1/n_RT) with the pooled within-sequence SD and df = n - 2; 90% CI), and assert that it equals the participant + period + formulation OLS model fitted with `lm()`. Recompute the geometric means (exp(mean(log x))) and geometric CV% (100 sqrt(exp(s^2) - 1)) and the AE participant counts (distinct USUBJID in the safety population). Compare with ADPP and `sim_lifecycle/out/results_summary.csv` at relative tolerance 1e-6.
- **Automatable:** all of it. Optional third engine: PKNCA 0.12.1 with `conc.blq = list(first = "keep", middle = "keep", last = "keep")`, `auc.method = "linear"` and the half-life fit given the same three points; skipped, and recorded as skipped, when PKNCA is not installed.
- **Human judgment:** whether a difference is a defect or a documented convention (for example nominal against actual sampling times); the sign-off.
- **Pass criterion:** every recomputed value within 1e-6 relative of the reported one; the closed form equals `lm()`; PKNCA, when it runs, agrees.
- **As implemented here:** `checks/independent_recompute.R` never sources the sandbox code (`simulate_adam.R`, `run_lifecycle.R`). The same author wrote both, so this is a same-author re-derivation, not double programming by a second person. Building it found a real defect: `nca_one()` dropped the predose zero, so AUClast left out the 0 to first-sample trapezoid and was 0.24% to 2.69% low on all 80 profiles; that was fixed (commit a9a9929) before this gate went in. On the committed outputs, 80 profiles agree with a maximum relative difference of 4.4e-10 (the summary file holds 10 significant digits), and PKNCA 0.12.1 agrees with the base-R recomputation.

### G10: Harness sensitivity gate (seeded defects)
**Claim it defends:** *"We know which realistic programming defects this harness catches, and which it misses."*

- **Do:** register a list of defects in advance (file, the exact text replaced, its replacement, the predicted catcher and the reasoning) and freeze it by its SHA-256. Plant each defect alone in a throwaway copy of the repository (never a branch); regenerate the outputs over the copy's committed outputs, so G1 cannot fire; run the other gates and the module tests; compare with an unmutated copy run the same way. Classify each defect CAUGHT (with the layers that failed), SURVIVED, EQUIVALENT (no output or printed result differs, shown by diff on the shipped data, so not proof that the change has no effect) or NOT APPLICABLE.
- **Automatable:** all of it: `teeth/run_teeth.sh` with `teeth/apply_defect.py`; tests in `teeth/tests/test_teeth.sh`.
- **Human judgment:** which defects belong on the list, and what to do about each survivor.
- **Pass criterion:** green while the last run used the current frozen registry and the current gate scripts, and every registry entry still applies; otherwise "stale". Survivors are disclosures of what the harness misses, not failures.
- **As implemented here:** see [the seeded-defect run](#the-seeded-defect-run-g10) below. The counts describe a hand-picked list, so they estimate nothing beyond it: no detection rate and no interval. QC-process engineering adapted from the teeth check and method-invariance grid in the author's consilience-engine software; it measures the harness and is not a statistical method.

---

## The seeded-defect run (G10)

The registry (`teeth/defects.csv`) gives, for each defect, the file, the exact text replaced, its
replacement, the predicted catcher and the reasoning. It is frozen by its SHA-256 in
`teeth/defects.sha256` and committed before each run; the runner refuses an edited registry.

- **Registry v1** (17 defects, D00 to D16; sha256 `6693bc70198f6a68c49ce9eee80f9dc053dec88ba07fa78f407703fd1cfa4e62`) was frozen in commit 2c36aa2 before the
  first run (commit 99adc6a). All 17 outcomes matched the predictions. That run's rows are kept in
  `teeth/results/teeth_2026-10-25_registry-v1.csv`.
- **A review probe then found a gap.** Changing the convention grid's lower window bound from `>=`
  to `>`, so that total bilirubin drawn on the same day as the aminotransferase draw no longer
  counts, failed no test and changed no output on the shipped data, so the runner filed it
  EQUIVALENT. No planted case and no study participant has its only qualifying TBL on the
  aminotransferase day. A same-day known-answer test was then added to `test-hyslaw-grid.R`.
- **Registry v2** (18 defects, D00 to D17; sha256 `e962ca98d30b2ac3b6c1db66d7271ea4f8beb2cb6b285606c2ea9f9c29d811d3`) was frozen in commit f0c75a2 before the
  second run. It adds D17, that lower-bound change, and corrects one sentence of D04's rationale
  (what G2 scans); no v1 prediction changed. D17's prediction was written after the test that
  catches it, so its catch shows the gap is closed, not that the tests were well designed.

The second run, on registry v2, was on 2026-10-25 with R 4.6.0
(`bash validation_harness/teeth/run_teeth.sh`, about 13 minutes); the unmutated copy passed
every layer. Results: `teeth/results/teeth_2026-10-25.csv` and `teeth/results/summary.json`.

| ID | Planted defect | Where | Result | Caught by |
|---|---|---|---|---|
| D00 | Comment-only edit (no-op control) | `run_lifecycle.R` | EQUIVALENT | nothing; no output or printed result differs (diff) |
| D01 | TRT01A wrong for one participant | `simulate_adam.R` `sim_adsl` | CAUGHT | the generator's own assertion, then G1 |
| D02 | PARAMCD AUCLST written as AUC-LST | `sim_adpp` | CAUGHT | driver error, G3, G9 |
| D03 | One ADAE USUBJID not in ADSL | `sim_adae` | CAUGHT | G3, G9 |
| D04 | exp(mean(x)) as the geometric mean in one R PK program | `r_tlf_pseudocode/crossover/t_pk_param_summary.R` | **SURVIVED** | nothing |
| D05 | exp(mean(x)) in `geo()` | `run_lifecycle.R` | CAUGHT | G9 only |
| D06 | AE overview counts records | `run_lifecycle.R` | CAUGHT | G9 only |
| D07 | log10 in `be()` | `run_lifecycle.R` | CAUGHT | G9 only |
| D08 | qt(0.975): a 95% CI printed as the 90% CI | `run_lifecycle.R` | CAUGHT | G9 only |
| D09 | Period term dropped from the BE model | `run_lifecycle.R` | CAUGHT | G9 only |
| D10 | lambda_z from two points | `nca_one()` | CAUGHT | G9 only |
| D11 | BLQ imputed as LLOQ/2 into AUC | `nca_one()` | CAUGHT | G9 only |
| D12 | Potential Hy's Law AND turned into OR | TRIALMON `logic.R` | CAUGHT | TRIALMON tests only (all four files) |
| D13 | TBL threshold 2x lowered to 1.5x ULN | TRIALMON `logic.R` | CAUGHT | TRIALMON tests only (all four files) |
| D14 | Grid window upper bound made exclusive | TRIALMON `hyslaw_grid.R` | CAUGHT | `test-hyslaw-grid.R` only |
| D15 | 5% predose exclusion skipped | n/a | NOT APPLICABLE | every predose concentration is 0 |
| D16 | AUC on nominal times | n/a | NOT APPLICABLE | ADPC has no actual-time variable |
| D17 | Grid window lower bound made strict (v2) | TRIALMON `hyslaw_grid.R` | CAUGHT | `test-hyslaw-grid.R` only; no shipped output changes |

Counts for registry v2: 14 caught, 1 survived, 1 equivalent, 2 not applicable. All 18 outcomes
matched the registered predictions, by this rule: a defect matches when its class is the
predicted one and every predicted catcher is among the layers that caught it. More catchers than
predicted still match. D12 and D13 were predicted to fail `test-logic.R` and `test-hyslaw-grid.R`;
they also failed `test-boundaries.R` and `test-server.R` (the `beyond_prediction` column of the
results lists such extra layers). The predictions were written by the person who wrote the gates,
after reading their code (and, for D06 and D11, the committed data), so the match shows the gates
behave as their author reads them; it is not an independent test.

EQUIVALENT is decided by diff on the shipped data: the runner compares the outputs and printed
results with those of the unmutated copy. A change that matters only for data the sandbox does
not contain is filed EQUIVALENT, so the class is not proof that a change has no effect. That is
how the v1 tests missed the lower-bound change that became D17.

What the run shows:

- **G1 to G8 caught none of the seven numeric and counting defects (D05 to D11).** Structural
  scans and byte-for-byte regeneration cannot see a wrong formula once the outputs are
  regenerated; only the separately written, same-author recomputation (G9) caught them.
- **D04 survived.** G2 counts files, not programs: it passes while the log-scale pattern appears
  in any file under `r_tlf_pseudocode`, documentation included, so it would pass even if no R
  program used the log scale; and no layer runs the TLF libraries on data. This is a disclosure of
  what the harness missed, not a failure of the run. G2 has since been changed to check each PK
  program (2026-10-26); D04 will be re-scored in the next seeded-defect run under a new registry
  version, frozen before that run.
- **D01 was caught earlier than the build spec predicted.** `simulate_study()` asserts that the
  ADSL period-1 TRT01A equals the ADEX period-1 TRTA, so the generator stops before G3's
  TRT01A-tracks-TRTSEQP check sees any data; that G3 check is not exercised by this list.
- **The harness does not run the TRIALMON tests.** D12 to D14 and D17 were caught only by
  `sasr_monitoring_wiki/trialmon_tests`; `run_harness.sh` alone would have reported green.
- The counts describe this hand-picked list. They estimate nothing beyond it, so there is no
  detection rate and no interval.

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
