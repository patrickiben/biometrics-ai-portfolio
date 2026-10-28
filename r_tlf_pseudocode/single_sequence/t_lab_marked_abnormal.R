################################################################################
# TABLE     : t_lab_marked_abnormal  (Single-/Fixed-Sequence DDI)
# TITLE     : Treatment-Emergent Markedly Abnormal Laboratory Values by Parameter
#             and Period
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADLB (PARAMCD/PARAM, ATOXGRN, BTOXGRN, ATOXGRH/ATOXGRL, ANRIND,
#             APERIOD/APERIODC, ONTRTFL)
# NOTE      : ANALYSIS TEMPLATE. "Markedly abnormal" = treatment-emergent CTCAE Grade
#             >=3 (post-baseline grade worse than within-period baseline grade),
#             matching the SAS twin. PERIOD table -> split by dv$byperiod
#             (APERIOD/APERIODC): Period 1 = reference (victim alone), Period 2 =
#             test (victim + perpetrator). Counts PARTICIPANTS (distinct USUBJID)
#             with >=1 qualifying value per analyte WITHIN PERIOD, split Low/High.
#             % denominator = on-treatment evaluable N from ADLB (SAFFL="Y" &
#             ONTRTFL="Y", distinct USUBJID per period) -- same source as SAS.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # byperiod = c("APERIOD","APERIODC")

# Preserve study-specific method: crossover uses limit multiples; other designs use supplied grades.
denom <- bign(check_analysis_units(adam$adlb) %>% filter(ONTRTFL=="Y"), dv$byperiod[2], "SAFFL")
tab <- marked_lab_summary(check_analysis_units(adam$adlb), dv$byperiod[2], denom, method="grade")
ttl <- tfl_titles("14.3.4.3", text="Participants with Markedly Abnormal Laboratory Values", foot="Markedly abnormal: supplied post-baseline grade at least the configured threshold and worse than supplied baseline grade. Missing grades or required limits remain unknown. Participants count once per parameter/criterion; Unknown evaluability may overlap a qualifying result at another visit. Denominator source: ADLB on-treatment evaluable safety population.")
print(tab)
