################################################################################
# TABLE     : t_ada_summary  (Parallel-group)
# TITLE     : Summary of Anti-Drug Antibody (ADA) Incidence by Treatment
# POPULATION: ADA-Evaluable Population (ADA-evaluable participants in ADIS)
# INPUT     : ADIS (immunogenicity: PARAMCD/PARAM = ADA / NAb status, baseline
#             and post-baseline; BASE/AVAL or status flags)
# NOTE      : ANALYSIS TEMPLATE. Counts = distinct PARTICIPANTS (n_distinct USUBJID), NOT
#             record rows. % denominator = ADA-evaluable N per treatment from a
#             period-/domain-bearing source (ADIS), NEVER one-row-per-participant
#             ADSL. Parallel-group: one treatment per participant -> column =
#             dv$trtvar (TRT01A, = dose for ascending-dose layouts).
#             Standard immunogenicity categories: baseline-positive,
#             treatment-induced, treatment-boosted, treatment-emergent (= induced
#             + boosted), persistent, transient, NAb-positive.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")                 # column = TRT01A (= dose)

rep <- ada_summary(adam$adis, dv$trtvar)
ttl <- tfl_titles("14.5.1.1", text="Summary of Anti-Drug Antibody Incidence", pop="ADA-Evaluable Population",
  foot="Denominator: distinct ADA-evaluable participants in ADIS by treatment. Classification uses supplied study-derived flags; unknown statuses are reported separately. Total counts each participant once. NAb percentage uses the ADA-evaluable population.")
print(rep)
