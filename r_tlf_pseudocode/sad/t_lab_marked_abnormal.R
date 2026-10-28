################################################################################
# TABLE     : t_lab_marked_abnormal  (Single Ascending Dose)
# TITLE     : Treatment-Emergent Markedly Abnormal Laboratory Values by Parameter
# POPULATION: Safety Population (SAFFL == "Y"), on-treatment evaluable
# INPUT     : ADLB (PARAMCD/PARAM, ATOXGR/ATOXGRN, BTOXGRN, ANRIND,
#             ATOXGRH/ATOXGRL, ONTRTFL)
# NOTE      : ANALYSIS TEMPLATE. SAD = parallel dose cohorts; column = DOSE LEVEL
#             (dv$trtvar = TRT01A), placebo pooled, + Total. "Markedly abnormal"
#             = treatment-emergent CTCAE Grade >=3 worsening, i.e. ATOXGRN >= 3
#             AND ATOXGRN > coalesce(BTOXGRN, 0) (post-baseline grade worse than
#             baseline). Direction (Low/High) carried from ATOXGRH/ATOXGRL or
#             ANRIND. Counts PARTICIPANTS (distinct USUBJID) with >=1 qualifying
#             post-baseline value per analyte; all gradable labs reported (no
#             PARAMCD restriction). Denominator = on-treatment evaluable N from
#             ADLB (SAFFL == "Y" & ONTRTFL == "Y", distinct USUBJID per dose level)
#             -- identical to the SAS twin denominator. Single dose: no period
#             structure. Useful as a dose-escalation safety read-out across cohorts.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                      # column = TRT01A (= dose level)

# Preserve study-specific method: crossover uses limit multiples; other designs use supplied grades.
denom <- bign(check_analysis_units(adam$adlb) %>% filter(ONTRTFL=="Y"), dv$trtvar, "SAFFL")
tab <- marked_lab_summary(check_analysis_units(adam$adlb), dv$trtvar, denom, method="grade")
ttl <- tfl_titles(num = "14.3.4.3", text="Participants with Markedly Abnormal Laboratory Values", foot="Markedly abnormal: supplied post-baseline grade at least the configured threshold and worse than supplied baseline grade. Missing grades or required limits remain unknown. Participants count once per parameter/criterion; Unknown evaluability may overlap a qualifying result at another visit. Denominator source: ADLB on-treatment evaluable safety population.")
print(tab)
