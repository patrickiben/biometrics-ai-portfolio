# Simulated Study Life Cycle — early-phase clin-pharm (synthetic)

A self-contained, runnable demo: one synthetic early-phase clinical-pharmacology study
taken end-to-end through the analysis tools — **synthetic ADaM → PK/NCA → TLF computations** —
to exercise the whole pipeline on realistically-shaped data.

## 100% synthetic

The **design structure** (design-model mix, enrollment-N distribution, healthy-volunteer
rate, randomization/masking, archetype mix, unit geography) is informed by public
early-phase **Phase-1 registration patterns on ClinicalTrials.gov**. **All participant-level
data is simulated** from generic domain priors (typical oral small-molecule PK, healthy-volunteer
AE incidence) — it is not fit to any specific sponsor, and no real participant-level data is used
or reproduced. This demonstrates the *tools and the life cycle*, not any real study's outcomes.

## Files

- `simulate_adam.R` — the synthetic ADaM generator (base R; priors baked in). Emits 8
  ADaM-shaped domains: **ADSL, ADEX, ADPC, ADPP, ADAE, ADVS, ADLB, ADEG**, with a
  one-compartment oral PK model + NCA, a 2×2 bioequivalence crossover option, and
  per-period safety domains.
- `priors.R` — the design + domain priors as a hardcoded list (no external data needed at runtime).
- `run_lifecycle.R` — driver: samples a design, simulates the study, and runs the
  demographics / **PK-NCA (geometric mean, log scale)** / **bioequivalence ANOVA (90% CI)** computations.
- `out/*.csv` — a generated synthetic study (seed 2026): the 8 ADaM domains.

## Run

```sh
Rscript sim_lifecycle/run_lifecycle.R
```

Base R only for the generator; deterministic (seeded). The output feeds the SAS/R TLF
pseudocode libraries in `../sas_tlf_pseudocode` and `../r_tlf_pseudocode`.

## Note on provenance

The public-registry **calibration corpus** (the ClinicalTrials.gov harvest that informed the
design-structure priors) is not included in this public repository; the priors it produced are
baked into `priors.R`, so the generator runs standalone.
