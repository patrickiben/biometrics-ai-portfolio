################################################################################
# TABLE     : t_ada_summary  (Crossover - 2x2 or Williams)
# TITLE     : Summary of Anti-Drug Antibody (ADA) Incidence by Treatment and
#             Period
# POPULATION: ADA-Evaluable Population (participants with >=1 ADA result on ADIS)
# INPUT     : ADIS (PARAMCD = ADA / NAB status; AVALC = Positive/Negative;
#             ABLFL baseline flag; APERIOD/APERIODC; TRTA; TRTSEQP)
# NOTE      : ANALYSIS TEMPLATE. Incidence = DISTINCT PARTICIPANTS (n_distinct(USUBJID)),
#             never row counts. Denominator = ADA-evaluable participants PER TREATMENT
#             and PER PERIOD taken from ADIS (period-bearing source), NOT ADSL.
#             Categories follow the standard ADA cascade:
#               - Baseline ADA-positive (pre-existing)
#               - Treatment-induced (baseline neg -> post-baseline pos)
#               - Treatment-boosted (baseline pos -> >= titer-fold rise)
#               - Treatment-emergent = induced + boosted
#               - NAb-positive among ADA-positive
#             Crossover: report by TRTA so each treatment's emergence is separable;
#             washout makes a participant ADA-status carry-over a key footnote.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # TRTA + APERIOD + TRTSEQP

rep <- ada_summary(adam$adis, dv$trtvar)
ttl <- tfl_titles("14.5.1.1", text="Summary of Anti-Drug Antibody Incidence", pop="ADA-Evaluable Population",
  foot="Denominator: distinct ADA-evaluable participants in ADIS by treatment. Classification uses supplied study-derived flags; unknown statuses are reported separately. Total counts each participant once. NAb percentage uses the ADA-evaluable population.")
print(rep)
by_period <- ada_summary(adam$adis, dv$trtvar, period=TRUE)
print(by_period)
