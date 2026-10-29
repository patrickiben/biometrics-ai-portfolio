################################################################################
# TABLE     : t_baseline_characteristics  (Parallel-group)
# TITLE     : Baseline Disease and Clinical Characteristics
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADSL  (+ baseline records from ADVS/ADLB if pulled via BASE)
# NOTE      : ANALYSIS TEMPLATE. Complements t_demographics: baseline clinical state
#             (vitals, eGFR/creatinine clearance, smoking/alcohol, baseline
#             disease severity). Continuous: n, Mean (SD), Median, Min-Max;
#             categorical: n (%). Columns = treatment arms (TRT01A) + Total.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")                 # -> trtvar = TRT01A, trtnvar = TRT01AN

tab <- baseline_summary(adam$adsl, dv$trtvar)
ttl <- tfl_titles(num = "14.1.3", text="Selected Baseline Clinical Characteristics", foot="Selected source fields and source units are reported without re-deriving clinical values. Percentages use the safety population by treatment or sequence. Missing categorical values are Unknown.")
print(tab)
