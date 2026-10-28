################################################################################
# TABLE     : t_ae_by_soc_pt  (Single-/fixed-sequence DDI)
# TITLE     : Treatment-Emergent Adverse Events by System Organ Class and
#             Preferred Term, by Period
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y"); ADEX for per-PERIOD dosed denominators
# NOTE      : ANALYSIS TEMPLATE. Columns = dv$byperiod (APERIODC): Period 1 reference
#             (victim alone), Period 2 test (victim + perpetrator). Counts =
#             PARTICIPANTS with >=1 event (n_distinct USUBJID), NOT event rows.
#             % denominator = participants DOSED per APERIOD (ADEX, SAFFL) -- NOT ADSL.
#             SOC sorted by overall frequency desc; PT within SOC desc.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # TRTA + APERIOD/APERIODC

# Planned safety columns come from the population source, including zero-event arms.
denom <- bign(adam$adex, dv$trtvar, "SAFFL")
adae <- adam$adae %>% filter(SAFFL == "Y", TRTEMFL == "Y")
rep <- ae_hierarchy(adae, dv$trtvar, denom)

ttl <- tfl_titles(num = "14.3.1.2", type = "Table",
   text = "Treatment-Emergent Adverse Events by System Organ Class and Preferred Term, by Period",
   pop  = "Safety Population",
   foot = paste("DDI: Period 1 = victim alone (reference); Period 2 = victim + perpetrator (test).",
                "A participant is counted once at each level within a period. % = participants / participants dosed in that period (ADEX).",
                "{meddra}."))

## rtables / gt rendering; SOC bold (level 1), PT indented (level 2)
print(rep)
