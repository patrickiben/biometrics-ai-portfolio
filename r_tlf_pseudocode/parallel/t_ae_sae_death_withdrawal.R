################################################################################
# TABLE     : t_ae_sae_death_withdrawal  (Parallel-group)
# TITLE     : Serious Adverse Events, Deaths, and Adverse Events Leading to
#             Study Drug Discontinuation by System Organ Class and Preferred Term
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y")
# NOTE      : ANALYSIS TEMPLATE. Three stacked panels (SAEs / Deaths / Discontinuations).
#             Counts = PARTICIPANTS (n_distinct USUBJID), NOT event rows. n (%) per
#             arm; % denominator = SAFFL N per arm. Parallel: column = TRT01A.
#             Fatal = AESDTH=="Y"; discontinuation = AEACN=="DRUG WITHDRAWN".
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")                  # trtvar = TRT01A

# Planned safety columns come from the population source, including zero-event arms.
denom <- bign(adam$adsl, dv$trtvar, "SAFFL")
adae <- adam$adae %>% filter(SAFFL == "Y", TRTEMFL == "Y")
rep <- bind_rows(
  ae_hierarchy(filter(adae, AESER == "Y"), dv$trtvar, denom, "Participants with any SAE") %>% mutate(panel="Serious Adverse Events"),
  ae_hierarchy(filter(adae, AESDTH == "Y" | toupper(AEOUT) == "FATAL"), dv$trtvar, denom, "Participants with fatal AE") %>% mutate(panel="Adverse Events with Fatal Outcome"),
  ae_hierarchy(filter(adae, AEACN == "DRUG WITHDRAWN"), dv$trtvar, denom, "Participants with AE leading to discontinuation") %>% mutate(panel="Adverse Events Leading to Discontinuation"))

ttl <- tfl_titles(
  num  = "14.3.1.4",
  type = "Table",
  text = "Serious Adverse Events, Deaths, and AEs Leading to Discontinuation by SOC and Preferred Term",
  pop  = "Safety Population",
  foot = paste("SAE = AESER==Y; fatal = AESDTH==Y; discontinuation = AEACN==DRUG WITHDRAWN.",
               "Treatment-emergent only (TRTEMFL=Y). A participant is counted once at each level",
               "within a panel. % = participants / N in arm. {meddra}."))

## rtables: split_rows_by(panel) outermost; within each, SOC bold, PT indented.
print(rep)
