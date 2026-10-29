################################################################################
# TABLE     : t_ae_by_relationship  (Crossover - 2x2 or Williams)
# TITLE     : Treatment-Related Treatment-Emergent Adverse Events by
#             System Organ Class and Preferred Term
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y"); ADEX for per-treatment denominators
# NOTE      : ANALYSIS TEMPLATE. Subset to RELATED TEAEs only, then count PARTICIPANTS
#             (n_distinct USUBJID), NOT event rows. "Related" set, case-safe:
#             toupper(AREL) %in% {RELATED, POSSIBLE, PROBABLE, DEFINITE}.
#             Columns = treatment (TRTA); % denominator = participants exposed to
#             that treatment from ADEX (period-bearing), NOT ADSL. SOC by overall
#             participant freq desc; PT within SOC desc.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("CROSSOVER")                 # trtvar=TRTA, byperiod=APERIOD/APERIODC

# Planned safety columns come from the population source, including zero-event arms.
denom <- bign(adam$adex, dv$trtvar, "SAFFL")
adae <- adam$adae %>% filter(SAFFL == "Y", TRTEMFL == "Y")
rel_set <- toupper(tfl_setting_codes("related_values", "RELATED,POSSIBLE,PROBABLE,DEFINITE"))
adae <- adae %>% filter(toupper(AREL) %in% toupper(rel_set))
rep <- ae_hierarchy(adae, dv$trtvar, denom, "Participants with any treatment-related TEAE")

ttl <- tfl_titles(num = "14.3.1.4", type = "Table",
   text = "Treatment-Related Treatment-Emergent Adverse Events by System Organ Class and Preferred Term",
   pop  = "Safety Population",
   foot = paste0("Related = AREL in {Related, Possible, Probable, Definite} (case-insensitive). ",
                 "A participant is counted once at each level. Columns = treatment (TRTA). % = participants / N exposed (ADEX). {meddra}."))

## rtables/gt rendering; SOC bold (level 1), PT indented (level 2)
ttl$footnotes <- c(paste("Configured relatedness values:",paste(rel_set,collapse=", ")),ttl$footnotes)
print(rep)
