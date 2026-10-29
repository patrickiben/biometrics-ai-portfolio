################################################################################
# TABLE     : t_ae_sae_death_withdrawal  (Crossover - 2x2 or Williams)
# TITLE     : Serious Adverse Events, Deaths, and Adverse Events Leading to
#             Withdrawal by System Organ Class and Preferred Term
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y"); ADEX for per-treatment denominators
# NOTE      : ANALYSIS TEMPLATE. Three stacked panels (SAE / Death / Withdrawal). Counts
#             = PARTICIPANTS (n_distinct USUBJID), NOT event rows. Columns =
#             treatment (TRTA), with AE attributed to the treatment in effect at
#             onset. % denominator = participants exposed to that treatment from ADEX
#             (period-bearing), NOT ADSL. SOC/PT ordered by participant freq desc
#             within each panel.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # trtvar=TRTA, byperiod=APERIOD/APERIODC

# Planned safety columns come from the population source, including zero-event arms.
denom <- bign(adam$adex, dv$trtvar, "SAFFL")
adae <- adam$adae %>% filter(SAFFL == "Y", TRTEMFL == "Y")
rep <- bind_rows(
  ae_hierarchy(filter(adae, AESER == "Y"), dv$trtvar, denom, "Participants with any SAE") %>% mutate(panel="Serious Adverse Events"),
  ae_hierarchy(filter(adae, AESDTH == "Y" | toupper(AEOUT) == "FATAL"), dv$trtvar, denom, "Participants with fatal AE") %>% mutate(panel="Adverse Events with Fatal Outcome"),
  ae_hierarchy(filter(adae, AEACN == "DRUG WITHDRAWN"), dv$trtvar, denom, "Participants with AE leading to discontinuation") %>% mutate(panel="Adverse Events Leading to Discontinuation"))

ttl <- tfl_titles(num = "14.3.1.5", type = "Table",
   text = "Serious Adverse Events, Deaths, and Adverse Events Leading to Withdrawal by SOC and PT",
   pop  = "Safety Population",
   foot = paste0("A participant is counted once at each level within each panel. Columns = treatment (TRTA). ",
                 "% = participants / N exposed (ADEX). SAE = AESER=Y; Death = AESDTH=Y; Withdrawal = AEACN='DRUG WITHDRAWN'. {meddra}."))

## rtables: row split on panel -> SOC -> PT; treatment columns + Total
print(rep)
