################################################################################
# TABLE     : t_lab_marked_abnormal  (Crossover - 2x2 or Williams)
# TITLE     : Participants with Markedly Abnormal (PCSA) Laboratory Values
#             by Treatment and Period
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADLB (PARAMCD; AVAL, A1HI, A1LO limits, ANRIND, R2ULN)
# NOTE      : ANALYSIS TEMPLATE. Counts of participants with >=1 potentially clinically
#             significant (markedly abnormal) post-baseline result, by direction
#             (High / Low) within each analyte. Crossover: assessed WITHIN each
#             treatment period and reported by actual treatment (dv$trtvar=TRTA);
#             a participant can be flagged under more than one treatment. HOUSE RULE:
#             guard limit comparisons with !is.na(A1HI)/!is.na(A1LO) before
#             classifying High vs Low. Counts = distinct participants (not rows);
#             denominator = treatment column N from bign().
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # trtvar = TRTA ; byperiod = APERIOD/APERIODC

# Preserve study-specific method: crossover uses limit multiples; other designs use supplied grades.
denom <- bign(adam$adex, dv$trtvar, "SAFFL")
tab <- marked_lab_summary(check_analysis_units(adam$adlb), dv$trtvar, denom, method="limits")
ttl <- tfl_titles("14.3.4.3", text="Participants with Markedly Abnormal Laboratory Values", foot="Markedly abnormal: configured multiples of upper/lower reference limits. Missing grades or required limits remain unknown. Participants count once per parameter/criterion; Unknown evaluability may overlap a qualifying result at another visit. Denominator source: ADEX dosed safety population.")
print(tab)
