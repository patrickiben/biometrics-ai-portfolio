################################################################################
# TABLE     : t_ae_sae_death_withdrawal  (Multiple Ascending Dose)
# TITLE     : Serious Adverse Events, Deaths, and Adverse Events Leading to
#             Study Drug Discontinuation by System Organ Class and Preferred
#             Term, by Dose Level
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y")
# NOTE      : ANALYSIS TEMPLATE. MAD = parallel ascending-dose cohorts, repeated dosing;
#             one treatment per participant, so column = dose level (dv$trtvar =
#             TRT01A) ordered ascending by TRT01AN. Three stacked panels (SAEs /
#             Deaths / Discontinuations). Counts = PARTICIPANTS (n_distinct USUBJID),
#             NOT event rows. n (%) per dose; % denominator = SAFFL N per dose.
#             Fatal = AESDTH=="Y"; discontinuation = AEACN=="DRUG WITHDRAWN".
#             In MAD the discontinuation panel is read against ascending dose to
#             support dose-escalation / stopping-rule review over the dosing
#             period.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                       # trtvar = TRT01A (dose level)

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
  foot = paste("MAD: parallel ascending-dose cohorts, repeated dosing; columns = dose",
               "level (ascending). SAE = AESER==Y; fatal = AESDTH==Y; discontinuation =",
               "AEACN==DRUG WITHDRAWN. Treatment-emergent only (TRTEMFL=Y). A participant is",
               "counted once at each level within a panel. % = participants / N at dose. {meddra}."))

## rtables: split_rows_by(panel) outermost; within each, SOC bold, PT indented;
## split_cols_by(dose) ascending.
print(rep)
