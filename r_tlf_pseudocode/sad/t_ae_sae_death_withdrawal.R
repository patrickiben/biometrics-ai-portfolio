################################################################################
# TABLE     : t_ae_sae_death_withdrawal  (Single Ascending Dose)
# TITLE     : Serious Adverse Events, Deaths, and Adverse Events Leading to
#             Study Drug Discontinuation by SOC and Preferred Term, by Dose Level
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y")
# NOTE      : ANALYSIS TEMPLATE. Three stacked panels (SAEs / Deaths / Discontinuations).
#             Counts = PARTICIPANTS (n_distinct USUBJID), NOT event rows. n (%) per
#             dose level; % denominator = SAFFL N per dose level. SAD: column =
#             dose level (dv$trtvar = TRT01A), ordered low->high (TRT01AN),
#             placebo often pooled. Fatal = AESDTH=="Y"; discontinuation =
#             AEACN=="DRUG WITHDRAWN". After a single dose, discontinuation is
#             typically rare but is retained for completeness / DLT context.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                       # trtvar = TRT01A

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
  text = "Serious Adverse Events, Deaths, and AEs Leading to Discontinuation by SOC and Preferred Term, by Dose Level",
  pop  = "Safety Population",
  foot = paste("SAD: each column = single ascending dose level (TRT01A), ordered",
               "low to high; placebo may be pooled. SAE = AESER==Y; fatal =",
               "AESDTH==Y; discontinuation = AEACN==DRUG WITHDRAWN. Treatment-",
               "emergent only (TRTEMFL=Y). A participant is counted once at each level",
               "within a panel. % = participants / N in dose level. {meddra}."))

## rtables: split_rows_by(panel) outermost; split_cols_by(dv$trtvar) (ascending
## dose); within each panel, SOC bold, PT indented.
print(rep)
