################################################################################
# TABLE     : t_ae_by_soc_pt  (Crossover - 2x2 or Williams)
# TITLE     : Treatment-Emergent Adverse Events by System Organ Class and
#             Preferred Term
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y"); ADEX for per-treatment denominators
# NOTE      : ANALYSIS TEMPLATE. Counts = PARTICIPANTS with >=1 event (n_distinct USUBJID),
#             NOT event rows. Columns = actual treatment (TRTA), since in a
#             crossover an AE is attributed to the treatment in effect when it
#             emerged. % denominator = participants exposed to that treatment from
#             ADEX (period-bearing), NOT ADSL. SOC sorted by overall participant
#             frequency desc; PT within SOC desc. An optional by-APERIOD split
#             (dv$byperiod) uses per-period ADEX denominators.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # trtvar=TRTA, byperiod=APERIOD/APERIODC

# Planned safety columns come from the population source, including zero-event arms.
denom <- bign(adam$adex, dv$trtvar, "SAFFL")
adae <- adam$adae %>% filter(SAFFL == "Y", TRTEMFL == "Y")
rep <- ae_hierarchy(adae, dv$trtvar, denom)

ttl <- tfl_titles(num = "14.3.1.2", type = "Table",
   text = "Treatment-Emergent Adverse Events by System Organ Class and Preferred Term",
   pop  = "Safety Population",
   foot = paste0("A participant is counted once at each level. Columns = actual treatment (TRTA); ",
                 "AE attributed to treatment in effect at onset. % = participants with the event / N exposed (ADEX). {meddra}."))

## rtables/gt rendering; SOC bold (level 1), PT indented (level 2)
print(rep)
