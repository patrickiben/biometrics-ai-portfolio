# Early-Phase Clinical Pharmacology: Runnable R TLF Library

Use the [point-and-click toolkit setup](https://patrickiben.github.io/biometrics-ai-portfolio/TOOLKIT_SETUP.html). Create a private project, select a design and outputs, map study CSV columns and review the analysis settings. Preview and generate the package, then use **Check**, **Install** (if packages are missing) and **Run analysis** on its revision card. No command-line steps or study-code edits are needed for supported analyses.

The library contains **221 runnable R programs** across five designs. R is the default execution engine for both TLF setup routes; paired native SAS source is exported as an unexecuted reference. The historical folder names preserve existing links.

Each attempt retains a separate report, every printed table/listing component as complete CSV and RDS, paginated HTML tables, PDF/PNG figures, software versions, recorded settings and execution QC. A failed selected output makes the run fail and exposes diagnostics. Computation does not approve a study result. QC uses synthetic data and known answers; study data, analysis populations, assumptions and suitability require review.

## Stack
`dplyr`/`tidyr`/`purrr` (derivation) · `rtables` (regulatory table layout) · `ggplot2` (figures) ·
`emmeans` + `lme4`/`lmerTest`/`nlme` (mixed models / BE) · `broom`/`broom.mixed` (tidy model output). It does
not use the pharmaverse production packages (`admiral` 1.5.0 for ADaM; `tern` 0.9.13 with `rtables`
0.6.17 for TLF layouts); it shows the underlying logic explicitly. Requires R >= 4.4.0
(execution QC on R 4.6.0).

## Designs (one folder each: full set per design)
| Folder | Design | Key analysis differences |
|---|---|---|
| `parallel/` | Parallel-group | Between-group; treatment = `TRT01A`/`TRT01AN` |
| `crossover/` | Crossover (supported BE model: nonreplicate 2×2) | Within-participant; by `APERIOD`/`TRTSEQP`; **BE/ANOVA** = `lmerTest` + `emmeans`, explicit Satterthwaite degrees of freedom, configurable GMR CI |
| `single_sequence/` | Single-/fixed-sequence (e.g. DDI) | By `APERIOD`; fixed order, **no** randomized sequence; ratio + 90% CI vs reference period |
| `sad/` | Single Ascending Dose | Parallel cohorts (dose = treatment); **dose-proportionality** (power model, `lm`) |
| `mad/` | Multiple Ascending Dose | Parallel cohorts, repeated dosing; **accumulation ratio** (Rac), descriptive trough trend over a configured window |

Design is wired via `design_vars("...")` in `00_setup_helpers.R` (returns `trtvar/trtnvar`,
`seqvar/seqvarn`, `byperiod`). Programs differ only where the **statistics** genuinely differ
(PK comparison, by-period/by-sequence safety, dose escalation); safety Tables/Listings are
structurally identical, re-pointed to the design's variables.

## TLF inventory (each = one script per design)
**Disposition / Demographics / Exposure** (ADSL, ADEX, ADCM, ADMH)
- `t_disposition` · `t_demographics` · `t_baseline_characteristics` · `t_exposure`
- `t_protocol_deviations` · `t_prior_con_meds` · `t_medical_history` · `l_disposition`

**Safety: AE** (ADAE): `t_ae_overview` · `t_ae_by_soc_pt` · `t_ae_by_severity` ·
`t_ae_by_relationship` · `t_ae_sae_death_withdrawal` · `l_ae` · `l_sae_death`

**Safety: Labs** (ADLB): `t_lab_summary` · `t_lab_shift` · `t_lab_marked_abnormal` ·
`f_lab_lft_scatter` · `f_lab_change` · `l_lab_abnormal`

**Safety: Vitals / ECG** (ADVS, ADEG): `t_vitals_summary` · `f_vitals_change` · `l_vitals` ·
`t_ecg_summary` · `t_ecg_qtc_categorical` · `f_qtc_change` · `l_ecg` · `t_cqtc_hysteresis` · `f_cqtc_hysteresis` (SAD, MAD;
an exploratory C-QTc hysteresis diagnostic linked to the synthetic method study in [`cqtc_hysteresis/`](../cqtc_hysteresis/index.html))

**PK** (ADPC, ADPP): `t_pk_conc_summary` · `l_pk_conc` · `f_pk_conc_mean` (linear+semilog) ·
`f_pk_conc_individual` · `t_pk_param_summary` · `l_pk_param` · `f_pk_param_boxplot` ·
design-specific `t_dose_proportionality` (SAD) · `t_accumulation` (MAD) · `t_be_anova` (crossover/single-seq)

**PD / Biomarkers** (ADPD): `t_pd_summary` · `f_pd_change` · `f_pkpd_overlay` · `l_pd`
**Immunogenicity** (ADIS): `t_ada_summary` · `t_ada_impact_pk` · `l_ada`

## Naming & conventions
`t_` table · `l_` listing · `f_` figure. One script → one output. Each script `source()`s
`00_setup_helpers.R`, calls `setup()`, gets `dv <- design_vars("<DESIGN>")`, then the TLF body.
Coding-dictionary versions are arguments of `setup()` (`meddra =`, `whodrug =`; defaults
`"MedDRA v29.1"` and `"WHODrug Global B3, Sep 2026"`); `tfl_titles()` writes them wherever a
footnote says `{meddra}` or `{whodrug}`. Set them to the versions the SAP names.

### House rules baked in (the same correctness lessons as the SAS twin)
- **Geometric PK stats on the log scale**: `geomean = exp(mean(log(x)))`, `geocv = 100*sqrt(exp(var(log(x)))-1)` never `exp(mean(raw))`.
- **Tmax = Median (Min, Max) only.**
- **Safety/AE counts = distinct participants** (`n_distinct(USUBJID)`), not event rows; `%` denominator = population N per column from `bign()`.
- **Per-period denominators come from a period-bearing source** (ADEX/ADIS/ADPD), NOT one-row-per-participant ADSL.
- **Single-sequence participant-level tables key on `dv$seqvar`/`dv$seqvarn`**; period tables use `dv$byperiod`.
- **Lab "worst" category = furthest from NORMAL**, with missing-limit guards (`!is.na(A1HI)` etc.).
- **No "eDISH" / "Hy's Law" terminology**: neutral liver-safety scatter ("Max ALT vs Total Bilirubin, ×ULN").

## ADaM variables relied on (no re-derivation)
Treatment `TRT01A/TRT01AN` (parallel) · `TRTA/TRTAN`+`APERIOD/APERIODC`+`TRTSEQP/TRTSEQPN` (crossover/seq);
populations `SAFFL/PKFL/ITTFL`; analysis `PARAMCD/AVAL/CHG/PCHG/BASE/AVISIT/ATPTN/ANRIND/BNRIND/A1HI/A1LO/R2ULN`;
AE `TRTEMFL/AESOC/AEDECOD/AESEVN/AREL/AESER/AESDTH/AEACN`; PK `ADPC AVAL=conc`, `ADPP PARAMCD=Cmax/Tmax/AUClast/AUCinf/CL/Vz/Rac`.

## Analysis choices and limits

- Enter actual numeric doses and their units for dose models; treatment order codes are never assumed to be doses.
- Configure reference/test labels, PK/PD parameter codes, confidence levels, comparison bounds and MAD analysis days in the forms.
- The crossover BE model supports complete nonreplicate 2×2 pairs. Fixed-sequence comparisons use a treatment mixed model on complete paired log observations with a participant random intercept and cannot separate treatment from period effects.
- Accumulation uses unique paired occasions. AUC ratios require confirmation that the two AUC intervals are comparable. A trough slope confidence interval containing zero is not proof of steady state.
- Log-scale PK summaries report excluded missing, nonpositive and BLQ values. Duplicate analysis records and incompatible units fail checks where applicable.
- Baseline covariates and lab thresholds are configurable. Missing ADA classifications and lab grades remain unknown; no-data cells do not become negative findings.
- C-QTc LINEAR/EMAX fits are exploratory diagnostics with explicit fit checks. They are not a qualified regulatory concentration-QTc workflow.
- Monitoring and interpretation reports use the same execution engine. LOCALMIND remains dependent on a separately installed model service and human review.

## QC

The reproducible suites cover all 221 programs on synthetic fixtures, minimal required-column contracts, numerical known answers, boundary and metamorphic tests, and report/export failure handling. See [QC_REPORT.md](../QC_REPORT.md) for the release's executed checks. No licensed SAS execution or independent study-specific double programming is claimed.
