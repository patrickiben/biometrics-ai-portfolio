################################################################################
# TABLE     : t_ae_by_relationship  (Multiple Ascending Dose)
# TITLE     : Treatment-Related Treatment-Emergent Adverse Events by System
#             Organ Class and Preferred Term, by Dose Level
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y" & AREL related)
# NOTE      : ANALYSIS TEMPLATE. MAD = parallel ascending-dose cohorts, repeated dosing;
#             one treatment per participant, so column = dose level (dv$trtvar =
#             TRT01A) ordered ascending by TRT01AN. Restricts to treatment-
#             RELATED TEAEs using the house "related" set, case-safe:
#             toupper(AREL) %in% {RELATED, POSSIBLE, PROBABLE, DEFINITE}.
#             Counts = PARTICIPANTS (n_distinct USUBJID), NOT event rows. n (%) per
#             dose; % denominator = SAFFL N per dose.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                       # trtvar = TRT01A (dose level)

# Planned safety columns come from the population source, including zero-event arms.
denom <- bign(adam$adsl, dv$trtvar, "SAFFL")
adae <- adam$adae %>% filter(SAFFL == "Y", TRTEMFL == "Y")
rel_set <- toupper(tfl_setting_codes("related_values", "RELATED,POSSIBLE,PROBABLE,DEFINITE"))
adae <- adae %>% filter(toupper(AREL) %in% toupper(rel_set))
rep <- ae_hierarchy(adae, dv$trtvar, denom, "Participants with any treatment-related TEAE")

ttl <- tfl_titles(
  num  = "14.3.1.3",
  type = "Table",
  text = "Treatment-Related Treatment-Emergent Adverse Events by SOC and Preferred Term, by Dose Level",
  pop  = "Safety Population",
  foot = paste("MAD: parallel ascending-dose cohorts, repeated dosing; columns = dose",
               "level (ascending). Treatment-related = AREL in {RELATED, POSSIBLE,",
               "PROBABLE, DEFINITE} (case-insensitive). A participant is counted once at each",
               "level. % = participants / N at dose. {meddra}."))

## rtables/gt: split_cols_by(dose, ascending); SOC bold (level 1), PT indented (level 2)
ttl$footnotes <- c(paste("Configured relatedness values:",paste(rel_set,collapse=", ")),ttl$footnotes)
print(rep)
