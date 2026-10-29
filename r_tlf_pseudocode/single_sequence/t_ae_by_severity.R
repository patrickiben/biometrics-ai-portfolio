################################################################################
# TABLE     : t_ae_by_severity  (Single-/fixed-sequence DDI)
# TITLE     : Treatment-Emergent Adverse Events by System Organ Class,
#             Preferred Term and Maximum Severity, by Period
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y"); ADEX for per-PERIOD dosed denominators
# NOTE      : ANALYSIS TEMPLATE. Columns nested: PERIOD (APERIODC) x severity (Mild/
#             Moderate/Severe). A participant is counted ONCE per PT at the MAXIMUM
#             severity reported within the period (max AESEVN per USUBJID*PT*per).
#             Counts = distinct PARTICIPANTS, NOT event rows. % denominator =
#             participants DOSED per APERIOD (ADEX, SAFFL) -- NOT ADSL.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # TRTA + APERIOD/APERIODC

# Planned safety columns come from the population source, including zero-event arms.
denom <- bign(adam$adex, dv$trtvar, "SAFFL")
adae <- adam$adae %>% filter(SAFFL == "Y", TRTEMFL == "Y")
rep <- ae_hierarchy(adae, dv$trtvar, denom, severity = TRUE)

ttl <- tfl_titles(num = "14.3.1.3", type = "Table",
   text = "Treatment-Emergent Adverse Events by SOC, Preferred Term and Maximum Severity, by Period",
   pop  = "Safety Population",
   foot = paste("DDI: Period 1 = victim alone (reference); Period 2 = victim + perpetrator (test).",
                "Severity = NCI-CTCAE grade collapsed to Mild/Moderate/Severe; participant counted once per PT at maximum severity within the period.",
                "% = participants / participants dosed in that period (ADEX). {meddra}."))

## rtables / gt: spanning PERIOD header over (Mild, Moderate, Severe) sub-columns
print(rep)
