################################################################################
# TABLE     : t_baseline_characteristics  (Single-/Fixed-Sequence DDI)
# TITLE     : Baseline Disease and Clinical Characteristics
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADSL (participant-level baseline *BL variables; categorical groups)
# NOTE      : ANALYSIS TEMPLATE. Baseline = pre-first-dose (Period 1 baseline = the
#             single study baseline before the victim-alone period). PARTICIPANT-
#             LEVEL table -> columns = the ONE fixed sequence (dv$seqvar). NO
#             per-period split (baseline is a single pre-treatment state).
#             Continuous baselines come from the ADSL *BL variables (EGFRBL,
#             SYSBPBL, DIABPBL, QTCFBL) -- same source/analyte set as the SAS
#             twin; eGFR and QTcF are retained for the renal/DDI design. The
#             DDI-relevant CYP metabolizer phenotype (CYPPHENO) block is included.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # seqvar = TRTSEQP, seqvarn = TRTSEQPN

tab <- baseline_summary(adam$adsl, dv$seqvar)
ttl <- tfl_titles(num = "14.1.3", text="Selected Baseline Clinical Characteristics", foot="Selected source fields and source units are reported without re-deriving clinical values. Percentages use the safety population by treatment or sequence. Missing categorical values are Unknown.")
print(tab)
