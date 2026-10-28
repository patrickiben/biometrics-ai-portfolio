################################################################################
# TABLE     : t_baseline_characteristics  (Multiple Ascending Dose)
# TITLE     : Baseline Disease and Clinical Characteristics by Dose Cohort
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADSL  (+ baseline records from ADVS/ADLB if pulled via BASE)
# NOTE      : ANALYSIS TEMPLATE. Complements t_demographics: baseline clinical state
#             (vitals, eGFR/creatinine clearance, smoking/alcohol, baseline
#             disease severity). Continuous: n, Mean (SD), Median, Min-Max;
#             categorical: n (%). MAD = parallel dose cohorts; columns = DOSE
#             LEVEL (TRT01A) with placebo pooled + Total. Participant-level table.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                       # -> trtvar = TRT01A (dose level), trtnvar = TRT01AN

tab <- baseline_summary(adam$adsl, dv$trtvar)
ttl <- tfl_titles(num = "14.1.3", text="Selected Baseline Clinical Characteristics", foot="Selected source fields and source units are reported without re-deriving clinical values. Percentages use the safety population by treatment or sequence. Missing categorical values are Unknown.")
print(tab)
