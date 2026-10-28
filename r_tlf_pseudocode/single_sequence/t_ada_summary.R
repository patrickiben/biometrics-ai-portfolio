################################################################################
# TABLE     : t_ada_summary  (Single-/Fixed-Sequence DDI)
# TITLE     : Summary of Anti-Drug Antibody (ADA) Incidence by Period
# POPULATION: ADA-Evaluable Population (ADA-evaluable participants in ADIS)
# INPUT     : ADIS (immunogenicity: PARAMCD/PARAM = ADA / NAb status, baseline
#             and post-baseline; BASE/AVAL or status flags; APERIOD/APERIODC)
# NOTE      : ANALYSIS TEMPLATE. Counts = distinct PARTICIPANTS (n_distinct USUBJID), NOT
#             record rows. PERIOD table -> columns = dv$byperiod (APERIODC):
#             Period 1 = reference (victim alone), Period 2 = test (victim +
#             perpetrator). NO randomized sequence. % denominator = ADA-evaluable
#             N PER PERIOD from a period-bearing source (ADIS), NEVER one-row-
#             per-participant ADSL. Standard immunogenicity categories: baseline-
#             positive, treatment-induced, treatment-boosted, treatment-emergent
#             (= induced + boosted), persistent, transient, NAb-positive.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # byperiod = c("APERIOD","APERIODC")

rep <- ada_summary(adam$adis, dv$trtvar)
ttl <- tfl_titles("14.5.1.1", text="Summary of Anti-Drug Antibody Incidence", pop="ADA-Evaluable Population",
  foot="Denominator: distinct ADA-evaluable participants in ADIS by treatment. Classification uses supplied study-derived flags; unknown statuses are reported separately. Total counts each participant once. NAb percentage uses the ADA-evaluable population.")
print(rep)
by_period <- ada_summary(adam$adis, dv$trtvar, period=TRUE)
print(by_period)
