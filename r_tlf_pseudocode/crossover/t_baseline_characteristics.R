################################################################################
# TABLE     : t_baseline_characteristics  (Crossover - 2x2 / Williams)
# TITLE     : Baseline Disease and Clinical Characteristics
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADSL  (study-entry baseline)  + ADVS/ADLB BASE (PERIOD-1 baselines)
# NOTE      : ANALYSIS TEMPLATE. PARTICIPANT-LEVEL table. STUDY-entry baselines (smoking,
#             child-bearing potential, baseline vitals/labs measured once at
#             screening) are fixed within participant -> columns = treatment SEQUENCE
#             (dv$seqvar = TRTSEQP) + Total. CAUTION: crossover trials also carry
#             a PERIOD-specific pre-dose baseline (BASE at ABLFL=="Y" within each
#             APERIOD); those belong in the by-period efficacy/PD/safety change
#             tables keyed on dv$byperiod, NOT here. This table is study-entry
#             characteristics only.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")   # seqvar = TRTSEQP (participant-level), byperiod for the caveat above

tab <- baseline_summary(adam$adsl, dv$seqvar)
ttl <- tfl_titles("14.1.3", text="Selected Baseline Clinical Characteristics", foot="Selected source fields and source units are reported without re-deriving clinical values. Percentages use the safety population by treatment or sequence. Missing categorical values are Unknown.")
print(tab)
