# Residual carryover and the ICH M13A 5% pre-dose rule (synthetic)

Use the [point-and-click toolkit setup](https://patrickiben.github.io/biometrics-ai-portfolio/TOOLKIT_SETUP.html) to create a private project, run the known-answer checks and reproduce the carryover study. Scenario changes require review of the source and its assumptions.

Tools built: runs. Exploratory operating-characteristics study on synthetic data. The carryover
algebra and the 5% pre-dose rule are established (Grizzle 1965; Senn, D'Angelo and Potvin 2004;
Ocaña, Sánchez and Carrasco 2015; ICH M13A). The subtraction analysis is a sensitivity analysis
only. Not regulatory guidance and not a validated method. Page: [`index.html`](index.html)
(results, known-answer checks, SAP wording, CSR shell, provenance and credit).

## What it does

A single-dose 2x2 crossover (n = 24, mean half-life 24 h) is simulated with period-1 drug carried
into period 2 by superposition, for washouts of 2 to 10 mean half-lives. Six analyses are compared:
an oracle with no residual, including everyone, the M13A exclusion rule, the rule's exclusion
decision alone, and subtraction of the extrapolated residual (estimated slope, and the true slope as
a diagnostic). Every operating characteristic is reported with its Monte Carlo standard error:
bias, consumer risk and power, 90% CI coverage, exclusions (by sequence), studies that are not
evaluable, and the M13A AUC coverage condition. The rule's leftover bias is split into selection and
retained residual.

Replicates are sized from a target MCSE of 0.005 at a rate of 0.05 (2,000 per cell). Random
numbers: L'Ecuyer-CMRG, seed 20261025, one stream per (true GMR, disposition) cell, and the same
participants reused across washouts, arms and configurations within a cell.

## Run

```sh
Rscript sim_lifecycle/carryover_oc/R/run_oc.R            # grid (about 10 s on 4 cores) and ADaM demonstration
Rscript sim_lifecycle/carryover_oc/tests/test_carryover.R  # T1 to T12; writes out/known_answer_checks.csv
Rscript sim_lifecycle/carryover_oc/R/tables.R              # T1 to T5, F1 to F3 and the page's numbers
```

From the repository root, base R 4.6.0. `OC_CORES=1` runs serially with byte-identical results.
The PKNCA cross-check in T2 runs only when PKNCA is installed.

## Files

| File | Contents |
|---|---|
| `R/dgm.R` | settings, participants, profiles, residual, assay error, closed form |
| `R/nca_m13a.R` | NCA for many profiles at once (AUC(0-t) from t = 0, BLQ as 0, last-3-point slope) |
| `R/analyze.R` | 2x2 estimator, the six arms, MCSEs, decomposition, random-number streams |
| `R/run_oc.R` | the full grid and the single-study ADaM demonstration |
| `R/tables.R` | tables, figures (light and dark PNG) and the generated blocks of `index.html` |
| `tests/test_carryover.R` | known-answer checks T1 to T12 and controls (T8 and T11 check the 5% rule and the wiring of every arm; T12 the MCSE formulas) |
| `out/oc_results.csv` | every configuration, true GMR, disposition, washout, arm and endpoint, with MCSEs and paired differences from the oracle |
| `out/oc_bias_decomposition.csv` | selection and retained residual, the selection share (delta-method MCSE) and the rule against including everyone, paired within study |
| `out/known_answer_checks.csv` | the pass table on the page |
| `out/adam_demo/` | ADPC and ADPP from `simulate_study(..., washout_h = 48)`; the other domains equal `sim_lifecycle/out` |

The `washout_h` option of `sim_lifecycle/simulate_adam.R` leaves the default output byte-identical
to the committed sandbox files (check T10).

Synthetic data only. Not real trial data.
