################################################################################
# TABLE     : t_ada_summary  (Multiple Ascending Dose)
# TITLE     : Summary of Anti-Drug Antibody (ADA) Incidence by Dose Level
# POPULATION: ADA-Evaluable Population (ADA-evaluable participants in ADIS)
# INPUT     : ADIS (immunogenicity: PARAMCD/PARAM = ADA / NAb status, baseline
#             and post-baseline; BASE/AVAL or status flags)
# NOTE      : ANALYSIS TEMPLATE. Counts = distinct PARTICIPANTS (n_distinct USUBJID), NOT
#             record rows. % denominator = ADA-evaluable N per DOSE LEVEL from a
#             domain-bearing source (ADIS), NEVER one-row-per-participant ADSL.
#             MAD = parallel cohorts, REPEATED dosing, one dose level per participant
#             -> column = dv$trtvar (TRT01A = dose level; placebo pooled).
#             Repeated dosing -> a longer multi-visit on-treatment immunogenicity
#             sampling window than SAD, so the persistent/transient split and a
#             max-titer read are more informative; categories are the standard
#             set: baseline-positive, treatment-induced, treatment-boosted,
#             treatment-emergent (= induced + boosted), persistent, transient,
#             NAb-positive. Participant-level status flags come from ADIS (validated
#             ADaM derivation); we count participants, not re-derive assay results.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                      # column = TRT01A (= dose level)

rep <- ada_summary(adam$adis, dv$trtvar)
ttl <- tfl_titles("14.5.1.1", text="Summary of Anti-Drug Antibody Incidence", pop="ADA-Evaluable Population",
  foot="Denominator: distinct ADA-evaluable participants in ADIS by treatment. Classification uses supplied study-derived flags; unknown statuses are reported separately. Total counts each participant once. NAb percentage uses the ADA-evaluable population.")
print(rep)
