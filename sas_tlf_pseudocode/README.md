# Early-Phase Clinical Pharmacology: SAS TLF Pseudocode Library

Use the [point-and-click toolkit setup](https://patrickiben.github.io/biometrics-ai-portfolio/TOOLKIT_SETUP.html) to choose design and outputs, upload study CSVs, map columns and run the corresponding R analyses. Both TLF setup routes use open-source R by default and retain native SAS reference exports. Check, install and run actions appear on the generated revision card. Native SAS source still requires a licensed SAS environment and review; it has not been executed or reconciled against R.


ADaM-based SAS **pseudocode** for every Table, Listing, and Figure (TLF) in an early-phase
clin-pharm study, with a **complete separate set per study design**. **SAS code not executed (no license):** none of these programs has been run in SAS. Illustrative
structure for specification and double programming, not validated production code; nothing here
originates a number. In a study, reported numbers come from validated, double-programmed SAS/R TLF programs on ADaM; NCA from Phoenix WinNonlin (version per ADRG, currently 8.8) or PKNCA; CDISC conformance is checked with Pinnacle 21 (FDA engine 2304.3), which produces no reported numbers.

## Designs (one folder each: full set per design)
| Folder | Design | Key analysis differences |
|---|---|---|
| `parallel/` | Parallel-group | Between-group; treatment = `TRT01A`/`TRT01AN` |
| `crossover/` | Crossover (2×2, Williams) | Within-participant; by `APERIOD`/`TRTSEQP`; **BE/ANOVA** (mixed model, GMR + 90% CI) |
| `single_sequence/` | Single-/fixed-sequence (e.g. DDI) | By `APERIOD`; fixed order, **no** randomized sequence; ratio + 90% CI vs reference period |
| `sad/` | Single Ascending Dose | Parallel cohorts (dose = treatment); **dose-proportionality** (power model) |
| `mad/` | Multiple Ascending Dose | Parallel cohorts, repeated dosing; **accumulation ratio** (Rac), steady-state assessment |

Design is also wired in code via `%designvars(design=...)` in `00_setup_macros.sas`, so each
design folder's programs differ only where the **statistics** genuinely differ (PK comparison,
by-period/by-sequence safety, dose escalation): Tables/Listings of safety are structurally
identical, re-pointed to the design's treatment/period variables.

## TLF inventory (each = one program per design)
**Disposition / Demographics / Exposure** (ADSL, ADEX, ADCM, ADMH)
- `t_disposition` · `t_demographics` · `t_baseline_characteristics` · `t_exposure`
- `t_protocol_deviations` · `t_prior_con_meds` · `t_medical_history` · `l_disposition`

**Safety: AE** (ADAE)
- `t_ae_overview` · `t_ae_by_soc_pt` · `t_ae_by_severity` · `t_ae_by_relationship`
- `t_ae_sae_death_withdrawal` · `l_ae` · `l_sae_death`

**Safety: Labs** (ADLB)
- `t_lab_summary` · `t_lab_shift` · `t_lab_marked_abnormal` · `f_lab_lft_scatter` · `f_lab_change` · `l_lab_abnormal`

**Safety: Vitals / ECG** (ADVS, ADEG)
- `t_vitals_summary` · `f_vitals_change` · `l_vitals`
- `t_ecg_summary` · `t_ecg_qtc_categorical` · `f_qtc_change` · `l_ecg`
- `t_cqtc_hysteresis` · `f_cqtc_hysteresis` (SAD, MAD): the prespecified C-QTc hysteresis check ([`cqtc_hysteresis/`](../cqtc_hysteresis/index.html))

**PK** (ADPC, ADPP)
- `t_pk_conc_summary` · `l_pk_conc` · `f_pk_conc_mean` (linear+semilog) · `f_pk_conc_individual`
- `t_pk_param_summary` · `l_pk_param` · `f_pk_param_boxplot`
- design-specific: `t_dose_proportionality` (SAD) · `t_accumulation` (MAD) · `t_be_anova` (crossover/single-seq)

**PD / Biomarkers** (ADPD): `t_pd_summary` · `f_pd_change` · `f_pkpd_overlay` · `l_pd`
**Immunogenicity** (ADIS): `t_ada_summary` · `t_ada_impact_pk` · `l_ada`

## Naming convention
`t_` table · `l_` listing · `f_` figure. One program → one output. Each program `%include`s
`00_setup_macros.sas`, calls `%setup` then `%designvars(design=<folder>)`, then the TLF body.
Coding-dictionary versions are parameters of `%setup` (`meddraver=`, `whodrugver=`; defaults
`MedDRA v29.1` and `WHODrug Global B3, Sep 2026`) and reach the footnotes as `&MEDDRAVER` and
`&WHODRUGVER`; set them to the versions the SAP names.

## ADaM variables relied on (no re-derivation here)
- Treatment: `TRT01A/TRT01AN` (parallel), `TRTA/TRTAN`+`APERIOD/APERIODC`+`TRTSEQP` (crossover/seq)
- Populations: `SAFFL`, `PKFL`, `ITTFL`, `RANDFL`
- Analysis: `PARAM/PARAMCD`, `AVAL`, `CHG`, `PCHG`, `BASE`, `AVISIT/AVISITN`, `ATPT/ATPTN`, `ANRIND`, `BNRIND`
- AE: `TRTEMFL`, `AESOC`, `AEDECOD`, `ASEV/AESEVN`, `AREL`, `AESER`, `AESDTH`, `AEACN`
- PK: `ADPC` AVAL=conc, `NRRELTM`/`ATPTN`=nominal time; `ADPP` PARAMCD=Cmax/Tmax/AUClast/AUCinf/CL/Vz/t1/2/Rac

## Status
Complete: **221 TLF programs** across all five design folders + `00_setup_macros.sas`. The four C-QTc hysteresis
programs (October 2026) postdate the panel review described next.
Generated with AI assistance, then reviewed by an AI-agent panel in two passes (six reviewers by
program family, then per-finding verification: 35 defects confirmed and fixed, 2 reviewer false
positives rejected), then a deterministic sweep; human sign-off is pending. Static checks confirm
that all programs scaffold correctly (`%include`/`%setup`/`%designvars`),
`%designvars` matches each folder, geometric PK stats are computed on the log scale (never
`exp(arithmetic mean)`), AE counts are distinct participants, single-sequence participant-level tables
key on `&SEQVAR`/`&SEQVARN` while period tables denominate from a period-bearing source, and the
library is free of `eDISH`/`Hy's Law` terminology. SAS code not executed (no license); written for
SAS 9.4M8 or later (9.4M9, June 2025, is current). Not validated production code.
