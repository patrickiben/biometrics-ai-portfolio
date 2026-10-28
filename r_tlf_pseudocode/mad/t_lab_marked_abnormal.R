################################################################################
# TABLE     : t_lab_marked_abnormal  (Multiple Ascending Dose)
# TITLE     : Treatment-Emergent Markedly Abnormal Laboratory Values by Dose Level
# POPULATION: Safety Population (SAFFL == "Y"), on-treatment evaluable
# INPUT     : ADLB (PARAMCD/PARAM, ATOXGRN, BTOXGRN, ATOXGRH, ATOXGRL, ANRIND,
#             ADY, ONTRTFL, SAFFL)
# NOTE      : ANALYSIS TEMPLATE. MAD = parallel dose cohorts with REPEATED dosing; column
#             variable = DOSE LEVEL (dv$trtvar = TRT01A) + Total. Marked abnormality
#             = TREATMENT-EMERGENT CTCAE Grade >= 3: ATOXGRN >= 3 AND
#             ATOXGRN > coalesce(BTOXGRN, 0) (post-baseline grade worse than baseline).
#             Direction (Low/High) from ATOXGRH/ATOXGRL (or ANRIND fallback). A
#             qualifying value at ANY on-treatment dosing day across the repeated-dose
#             period flags the participant. Counts = distinct USUBJID; % denominator =
#             on-treatment evaluable N from ADLB (SAFFL='Y' & ONTRTFL='Y', distinct
#             USUBJID). Fold-of-limit (xULN/xLLN) logic NOT used.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                      # column = TRT01A (= dose level)

# Preserve study-specific method: crossover uses limit multiples; other designs use supplied grades.
denom <- bign(check_analysis_units(adam$adlb) %>% filter(ONTRTFL=="Y"), dv$trtvar, "SAFFL")
tab <- marked_lab_summary(check_analysis_units(adam$adlb), dv$trtvar, denom, method="grade")
ttl <- tfl_titles(num = "14.3.4.3", text="Participants with Markedly Abnormal Laboratory Values", foot="Markedly abnormal: supplied post-baseline grade at least the configured threshold and worse than supplied baseline grade. Missing grades or required limits remain unknown. Participants count once per parameter/criterion; Unknown evaluability may overlap a qualifying result at another visit. Denominator source: ADLB on-treatment evaluable safety population.")
print(tab)
