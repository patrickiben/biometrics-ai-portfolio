################################################################################
# TABLE     : t_ae_by_relationship  (Single-/fixed-sequence DDI)
# TITLE     : Treatment-Related Adverse Events by System Organ Class and
#             Preferred Term, by Period
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y"); ADEX for per-PERIOD dosed denominators
# NOTE      : ANALYSIS TEMPLATE. Restricted to RELATED TEAEs. "Related" set is consistent
#             and case-safe: toupper(AREL) %in% c("RELATED","POSSIBLE","PROBABLE",
#             "DEFINITE"). Columns = dv$byperiod (APERIODC): Period 1 reference
#             (victim alone), Period 2 test (victim + perpetrator). Counts =
#             distinct PARTICIPANTS, NOT event rows. % denominator = participants DOSED
#             per APERIOD (ADEX, SAFFL) -- NOT ADSL.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # TRTA + APERIOD/APERIODC

# Planned safety columns come from the population source, including zero-event arms.
denom <- bign(adam$adex, dv$trtvar, "SAFFL")
adae <- adam$adae %>% filter(SAFFL == "Y", TRTEMFL == "Y")
rel_set <- toupper(tfl_setting_codes("related_values", "RELATED,POSSIBLE,PROBABLE,DEFINITE"))
adae <- adae %>% filter(toupper(AREL) %in% toupper(rel_set))
rep <- ae_hierarchy(adae, dv$trtvar, denom, "Participants with any treatment-related TEAE")

ttl <- tfl_titles(num = "14.3.1.4", type = "Table",
   text = "Treatment-Related Adverse Events by System Organ Class and Preferred Term, by Period",
   pop  = "Safety Population",
   foot = paste("DDI: Period 1 = victim alone (reference); Period 2 = victim + perpetrator (test).",
                "Related = AREL in Related/Possible/Probable/Definite (case-insensitive). Participant counted once at each level within a period.",
                "% = participants / participants dosed in that period (ADEX). {meddra}."))

## rtables / gt rendering; SOC bold (level 1), PT indented (level 2)
ttl$footnotes <- c(paste("Configured relatedness values:",paste(rel_set,collapse=", ")),ttl$footnotes)
print(rep)
