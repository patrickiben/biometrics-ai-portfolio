# Early-Phase Clinical Pharmacology — R TLF Pseudocode Library

R twin of `../sas_tlf_pseudocode/`. ADaM-based R **pseudocode** for every Table, Listing, and
Figure (TLF) in an early-phase clin-pharm study, with a **complete separate set per study design**.
Illustrative structure for spec/double-programming — not validated production code. Reported numbers
come from validated tools (Phoenix WinNonlin, Pinnacle 21, EDC) per SOP; nothing here originates a
reported number.

## Stack
`dplyr`/`tidyr`/`purrr` (derivation) · `rtables` (regulatory table layout) · `ggplot2` (figures) ·
`emmeans` + `lme4`/`nlme` (mixed models / BE) · `broom`/`broom.mixed` (tidy model output). The
higher-level **pharmaverse** path (`admiral` for ADaM, `tern` for pre-built TLF layouts) is the
production route; this library shows the underlying logic explicitly. R runs laptop-only per SOP.

## Designs (one folder each — full set per design)
| Folder | Design | Key analysis differences |
|---|---|---|
| `parallel/` | Parallel-group | Between-group; treatment = `TRT01A`/`TRT01AN` |
| `crossover/` | Crossover (2×2, Williams) | Within-participant; by `APERIOD`/`TRTSEQP`; **BE/ANOVA** = `lmer` + `emmeans`, GMR + 90% CI |
| `single_sequence/` | Single-/fixed-sequence (e.g. DDI) | By `APERIOD`; fixed order, **no** randomized sequence; ratio + 90% CI vs reference period |
| `sad/` | Single Ascending Dose | Parallel cohorts (dose = treatment); **dose-proportionality** (power model, `lm`) |
| `mad/` | Multiple Ascending Dose | Parallel cohorts, repeated dosing; **accumulation ratio** (Rac), steady-state assessment |

Design is wired via `design_vars("...")` in `00_setup_helpers.R` (returns `trtvar/trtnvar`,
`seqvar/seqvarn`, `byperiod`). Programs differ only where the **statistics** genuinely differ
(PK comparison, by-period/by-sequence safety, dose escalation); safety Tables/Listings are
structurally identical, re-pointed to the design's variables.

## TLF inventory (each = one script per design)
**Disposition / Demographics / Exposure** (ADSL, ADEX, ADCM, ADMH)
- `t_disposition` · `t_demographics` · `t_baseline_characteristics` · `t_exposure`
- `t_protocol_deviations` · `t_prior_con_meds` · `t_medical_history` · `l_disposition`

**Safety — AE** (ADAE) — `t_ae_overview` · `t_ae_by_soc_pt` · `t_ae_by_severity` ·
`t_ae_by_relationship` · `t_ae_sae_death_withdrawal` · `l_ae` · `l_sae_death`

**Safety — Labs** (ADLB) — `t_lab_summary` · `t_lab_shift` · `t_lab_marked_abnormal` ·
`f_lab_lft_scatter` · `f_lab_change` · `l_lab_abnormal`

**Safety — Vitals / ECG** (ADVS, ADEG) — `t_vitals_summary` · `f_vitals_change` · `l_vitals` ·
`t_ecg_summary` · `t_ecg_qtc_categorical` · `f_qtc_change` · `l_ecg`

**PK** (ADPC, ADPP) — `t_pk_conc_summary` · `l_pk_conc` · `f_pk_conc_mean` (linear+semilog) ·
`f_pk_conc_individual` · `t_pk_param_summary` · `l_pk_param` · `f_pk_param_boxplot` ·
design-specific `t_dose_proportionality` (SAD) · `t_accumulation` (MAD) · `t_be_anova` (crossover/single-seq)

**PD / Biomarkers** (ADPD) — `t_pd_summary` · `f_pd_change` · `f_pkpd_overlay` · `l_pd`
**Immunogenicity** (ADIS) — `t_ada_summary` · `t_ada_impact_pk` · `l_ada`

## Naming & conventions
`t_` table · `l_` listing · `f_` figure. One script → one output. Each script `source()`s
`00_setup_helpers.R`, calls `setup()`, gets `dv <- design_vars("<DESIGN>")`, then the TLF body.

### House rules baked in (the same correctness lessons as the SAS twin)
- **Geometric PK stats on the log scale**: `geomean = exp(mean(log(x)))`, `geocv = 100*sqrt(exp(var(log(x)))-1)` — never `exp(mean(raw))`.
- **Tmax = Median (Min, Max) only.**
- **Safety/AE counts = distinct participants** (`n_distinct(USUBJID)`), not event rows; `%` denominator = population N per column from `bign()`.
- **Per-period denominators come from a period-bearing source** (ADEX/ADIS/ADPD), NOT one-row-per-participant ADSL.
- **Single-sequence participant-level tables key on `dv$seqvar`/`dv$seqvarn`**; period tables use `dv$byperiod`.
- **Lab "worst" category = furthest from NORMAL**, with missing-limit guards (`!is.na(A1HI)` etc.).
- **No "eDISH" / "Hy's Law" terminology** — neutral liver-safety scatter ("Max ALT vs Total Bilirubin, ×ULN").

## ADaM variables relied on (no re-derivation)
Treatment `TRT01A/TRT01AN` (parallel) · `TRTA/TRTAN`+`APERIOD/APERIODC`+`TRTSEQP/TRTSEQPN` (crossover/seq);
populations `SAFFL/PKFL/ITTFL`; analysis `PARAMCD/AVAL/CHG/PCHG/BASE/AVISIT/ATPTN/ANRIND/BNRIND/A1HI/A1LO/R2ULN`;
AE `TRTEMFL/AESOC/AEDECOD/AESEVN/AREL/AESER/AESDTH/AEACN`; PK `ADPC AVAL=conc`, `ADPP PARAMCD=Cmax/Tmax/AUClast/AUCinf/CL/Vz/Rac`.

## Status
Complete: **217 TLF scripts** across all five design folders + `00_setup_helpers.R`. Built mirroring the
SAS twin with all its QC fixes pre-applied, then re-QC'd (6 family reviewers → per-finding verification:
24 findings, **14 confirmed P0/P1 fixed**, 0 false-positives), then a deterministic sweep. **All 218
scripts parse under `Rscript`**, `design_vars()` matches every folder, geometric PK stats compute on the
log scale, AE/safety counts are distinct participants, single-sequence participant-level tables key on
`dv$seqvar`, period tables denominate from a period-bearing source, exposure uses ADaM `AVAL`/`TRTDURD`/
`NDOSES` (no `*DTC` arithmetic), and the library is free of `eDISH`/`Hy's Law` terminology. Pseudocode for
spec/double-programming — reported numbers still come from validated tools per SOP.
