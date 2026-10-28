################################################################################
# TABLE     : t_lab_marked_abnormal  (Parallel-group)
# TITLE     : Treatment-Emergent Markedly Abnormal Laboratory Values by Parameter
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADLB (PARAMCD/PARAM, ATOXGRN/BTOXGRN, ANRIND, ONTRTFL)
# NOTE      : ANALYSIS TEMPLATE. "Markedly abnormal" = treatment-emergent CTCAE Grade >=3
#             (post-baseline grade worse than baseline grade), matching the SAS
#             twin. Counts = distinct USUBJID with >=1 qualifying post-baseline
#             value per analyte; % denominator = SAFFL N per arm from bign().
#             Per parameter three criterion rows are reported: Any Markedly
#             Abnormal, Markedly High, Markedly Low. Direction (High/Low) from
#             ANRIND; "Any" counts all qualifying records regardless of
#             direction. Columns = treatment arms (= dose level) + Total.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")                 # column = TRT01A (= dose level)

# Preserve study-specific method: crossover uses limit multiples; other designs use supplied grades.
denom <- bign(adam$adsl, dv$trtvar, "SAFFL")
tab <- marked_lab_summary(check_analysis_units(adam$adlb), dv$trtvar, denom, method="grade")
ttl <- tfl_titles("14.3.4.3", text="Participants with Markedly Abnormal Laboratory Values", foot="Markedly abnormal: supplied post-baseline grade at least the configured threshold and worse than supplied baseline grade. Missing grades or required limits remain unknown. Participants count once per parameter/criterion; Unknown evaluability may overlap a qualifying result at another visit. Denominator source: ADSL safety population.")
print(tab)
