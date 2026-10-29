################################################################################
# TABLE     : t_ada_summary  (Single Ascending Dose)
# TITLE     : Summary of Anti-Drug Antibody (ADA) Incidence by Dose Level
# POPULATION: ADA-Evaluable Population (ADA-evaluable participants in ADIS)
# INPUT     : ADIS (immunogenicity: PARAMCD/PARAM = ADA / NAb status, baseline
#             and post-baseline; BASE/AVAL or status flags)
# NOTE      : ANALYSIS TEMPLATE. Counts = distinct PARTICIPANTS (n_distinct USUBJID), NOT
#             record rows. % denominator = ADA-evaluable population N per DOSE
#             LEVEL from the ADSL ADAFL flag (bign), the SAME source as the SAS
#             twin -- so both deliverables share one ADA-evaluable denominator.
#             SAD = parallel cohorts, one dose per participant -> column = dv$trtvar
#             (TRT01A = dose level; placebo pooled). Single dose -> a short
#             single-dose follow-up window for immunogenicity; categories are
#             still the standard set: baseline-positive, treatment-induced,
#             treatment-boosted, treatment-emergent (= induced + boosted),
#             persistent, transient, NAb-positive.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                      # column = TRT01A (= dose level)

rep <- ada_summary(adam$adis, dv$trtvar)
ttl <- tfl_titles(num = "14.5.1.1", text="Summary of Anti-Drug Antibody Incidence", pop="ADA-Evaluable Population",
  foot="Denominator: distinct ADA-evaluable participants in ADIS by treatment. Classification uses supplied study-derived flags; unknown statuses are reported separately. Total counts each participant once. NAb percentage uses the ADA-evaluable population.")
print(rep)
