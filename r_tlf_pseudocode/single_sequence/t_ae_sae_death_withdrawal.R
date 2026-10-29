################################################################################
# TABLE     : t_ae_sae_death_withdrawal  (Single-/fixed-sequence DDI)
# TITLE     : Serious Adverse Events, Deaths, and AEs Leading to Withdrawal
#             by System Organ Class and Preferred Term, by Period
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y"); ADEX for per-PERIOD dosed denominators
# NOTE      : ANALYSIS TEMPLATE. Three stacked blocks (SAE / Death / Withdrawal), each
#             with a header participant-count row + SOC*PT detail (row label
#             "SOC: PT", same granularity/format as the SAS twin). Columns =
#             dv$byperiod (APERIODC): Period 1 reference (victim alone), Period 2
#             test (victim + perpetrator). Counts = distinct PARTICIPANTS, NOT
#             event rows. % denominator = participants DOSED per APERIOD (ADEX,
#             SAFFL) -- NOT ADSL.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # TRTA + APERIOD/APERIODC

# Planned safety columns come from the population source, including zero-event arms.
denom <- bign(adam$adex, dv$trtvar, "SAFFL")
adae <- adam$adae %>% filter(SAFFL == "Y", TRTEMFL == "Y")
rep <- bind_rows(
  ae_hierarchy(filter(adae, AESER == "Y"), dv$trtvar, denom, "Participants with any SAE") %>% mutate(panel="Serious Adverse Events"),
  ae_hierarchy(filter(adae, AESDTH == "Y" | toupper(AEOUT) == "FATAL"), dv$trtvar, denom, "Participants with fatal AE") %>% mutate(panel="Adverse Events with Fatal Outcome"),
  ae_hierarchy(filter(adae, AEACN == "DRUG WITHDRAWN"), dv$trtvar, denom, "Participants with AE leading to discontinuation") %>% mutate(panel="Adverse Events Leading to Discontinuation"))

ttl <- tfl_titles(num = "14.3.1.5", type = "Table",
   text = "Serious Adverse Events, Deaths, and AEs Leading to Withdrawal by System Organ Class and Preferred Term, by Period",
   pop  = "Safety Population",
   foot = paste("DDI: Period 1 = victim alone (reference); Period 2 = victim + perpetrator (test).",
                "Participant counted once per block per period; SOC*PT detail counts participants once per SOC/PT. SAE per AESER; death per AESDTH; withdrawal per AEACN.",
                "% = participants / participants dosed in that period (ADEX). {meddra}."))

## rtables / gt: three stacked blocks (SAE, Death, Withdrawal), PT indented
print(rep)
