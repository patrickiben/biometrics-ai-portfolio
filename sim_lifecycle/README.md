# PK, NCA and bioequivalence sandbox (synthetic)

One synthetic early-phase clinical pharmacology study, taken through the analysis steps:
**synthetic ADaM, PK and NCA, then summary computations.** Base R, seeded, runs offline.
Page: [`index.html`](index.html).

## What it does

- `simulate_adam.R` writes eight ADaM-shaped domains: **ADSL, ADEX, ADPC, ADPP, ADAE, ADVS,
  ADLB, ADEG**. PK comes from a one-compartment oral model; NCA uses the linear trapezoidal
  rule, a terminal slope fitted to the last three points, and AUC to infinity, CL/F and Vz/F.
- The design is a 2x2 bioequivalence crossover with per-period safety domains (N = 40, seed 2026).
- `run_lifecycle.R` prints demographics, geometric means and geometric CV% on the log scale, the
  bioequivalence analysis (fixed-effects model on log values with participant, period and
  treatment; geometric mean ratio and 90% confidence interval), an adverse-event overview counted
  by participant, and vitals, lab and ECG summaries. It then writes `out/*.csv`.
- `priors.R` holds the design and domain priors as a hard-coded list.
- `simulate_study(..., washout_h = NULL)`: setting `washout_h` (hours between the two doses)
  adds each participant's period-1 residual to the period-2 profile by superposition, with no
  new random draws, and adds the ICH M13A pre-dose ratio `PDCMXR`, `ANL02FL` and `PKEXRSN` to
  ADPP. Left unset, the output is byte-identical to the committed files. The
  [residual-carryover study](carryover_oc/index.html) in `carryover_oc/` uses it.

## Run

```sh
Rscript sim_lifecycle/run_lifecycle.R
```

Run from the repository root. Base R only (tested with R 4.6.0). The run regenerates the
committed `out/*.csv` files byte for byte (checked 2026-10-24); the validation harness G1 gate
checks the same thing.

## What it is not

- Not a validated NCA: nominal sampling times and a fixed three-point terminal fit. In a study,
  NCA comes from a validated system such as Phoenix WinNonlin or a qualified PKNCA setup.
- Not checked by Pinnacle 21 or CDISC CORE; the domains pass this repository's own structural
  checks (`validation_harness/checks/conformance.R`).
- The drafting step (`tlf_interpret/`) is a stub when no language model is installed; only its
  number check runs.
- The SAS and R TLF libraries are written against these domain shapes but have not yet been run
  on these files.

## Synthetic data only

The **design structure** (design mix, enrollment size, healthy-volunteer rate, randomization
and masking, site geography) follows public Phase 1 registration patterns on ClinicalTrials.gov.
**All participant-level data is simulated** from generic priors (typical oral small-molecule PK,
healthy-volunteer adverse-event rates). It is not fitted to any sponsor, and no real participant
data is used or reproduced.

## Provenance of the calibration targets

The calibration targets printed by the driver (for example Cmax CV 36%) were fitted from 42
public early-phase registrations harvested from ClinicalTrials.gov. That harvest is not included
in this repository, so the targets cannot be re-derived here; the priors it produced are written
into `priors.R`, so the generator runs standalone.
