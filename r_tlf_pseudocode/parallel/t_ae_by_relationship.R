################################################################################
# TABLE     : t_ae_by_relationship  (Parallel-group)
# TITLE     : Treatment-Related Treatment-Emergent Adverse Events by System
#             Organ Class and Preferred Term
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y" & AREL related)
# NOTE      : ANALYSIS TEMPLATE. Restricts to treatment-RELATED TEAEs using the house
#             "related" set, case-safe: toupper(AREL) %in%
#             {RELATED, POSSIBLE, PROBABLE, DEFINITE}. Counts = PARTICIPANTS
#             (n_distinct USUBJID), NOT event rows. n (%) per arm; % denominator
#             = SAFFL N per arm. Parallel: column = TRT01A.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")                  # trtvar = TRT01A

# Planned safety columns come from the population source, including zero-event arms.
denom <- bign(adam$adsl, dv$trtvar, "SAFFL")
adae <- adam$adae %>% filter(SAFFL == "Y", TRTEMFL == "Y")
rel_set <- toupper(tfl_setting_codes("related_values", "RELATED,POSSIBLE,PROBABLE,DEFINITE"))
adae <- adae %>% filter(toupper(AREL) %in% toupper(rel_set))
rep <- ae_hierarchy(adae, dv$trtvar, denom, "Participants with any treatment-related TEAE")

ttl <- tfl_titles(
  num  = "14.3.1.3",
  type = "Table",
  text = "Treatment-Related Treatment-Emergent Adverse Events by SOC and Preferred Term",
  pop  = "Safety Population",
  foot = paste("Treatment-related = AREL in {RELATED, POSSIBLE, PROBABLE, DEFINITE}",
               "(case-insensitive). A participant is counted once at each level.",
               "% = participants / N in arm. {meddra}."))

## rtables/gt: SOC bold (level 1), PT indented (level 2)
ttl$footnotes <- c(paste("Configured relatedness values:",paste(rel_set,collapse=", ")),ttl$footnotes)
print(rep)
