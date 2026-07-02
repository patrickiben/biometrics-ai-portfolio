################################################################################
# TABLE     : t_ae_overview  (Single-/fixed-sequence DDI)
# TITLE     : Overview of Treatment-Emergent Adverse Events by Period
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y"); ADEX for per-PERIOD dosed denominators
# NOTE      : PSEUDOCODE. Single-/fixed-sequence DDI: Period 1 = reference
#             (victim alone), Period 2 = test (victim + perpetrator). Columns =
#             dv$byperiod (APERIODC); per-PERIOD denominators = participants dosed in
#             that APERIOD per ADEX (SAFFL=="Y") -- NEVER ADSL. Counts = PARTICIPANTS
#             with >=1 event (n_distinct USUBJID), NOT event rows. "Related" set
#             is case-safe: toupper(AREL) %in% RELATED/POSSIBLE/PROBABLE/DEFINITE.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # TRTA + APERIOD/APERIODC; fixed seq

period_col <- dv$byperiod[2]                    # "APERIODC" — readable period label

## --- per-PERIOD denominator: participants DOSED in each APERIOD (ADEX, SAFFL) -----
## A one-row-per-participant ADSL N would be wrong here: DDI periods can differ in
## who got dosed (e.g. Period 2 perpetrator add-on). Denominator is period-bearing.
denom <- adam$adex %>%
  filter(SAFFL == "Y") %>%
  group_by(per = .data[[period_col]]) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop") %>%
  bind_rows(tibble(per = "Total", N = n_distinct(adam$adex$USUBJID[adam$adex$SAFFL == "Y"])))

adae <- adam$adae %>% filter(SAFFL == "Y", TRTEMFL == "Y")

## --- category builder: distinct participants per period meeting a condition -------
ae_cat <- function(label, where) {
  d <- adae %>% filter(!!where)
  per <- d %>% group_by(per = .data[[period_col]]) %>%
    summarise(nsubj = n_distinct(USUBJID), .groups = "drop")
  tot <- tibble(per = "Total", nsubj = n_distinct(d$USUBJID))
  bind_rows(per, tot) %>% mutate(category = label)
}

rel_set <- c("RELATED","POSSIBLE","PROBABLE","DEFINITE")

## Canonical 6-category AE overview, same set/order as the SAS twin:
## any TEAE / serious / drug-related / severe / leading-to-disc / leading-to-death.
overview <- bind_rows(
  ae_cat("Participants with any TEAE",                       quote(TRUE)),
  ae_cat("Participants with any serious TEAE",               quote(AESER == "Y")),
  ae_cat("Participants with any drug-related TEAE",          quote(toupper(AREL) %in% rel_set)),
  ae_cat("Participants with any severe TEAE",                quote(AESEVN >= 3)),
  ae_cat("TEAE leading to study-drug discontinuation",       quote(str_detect(toupper(AEACN), "DRUG WITHDRAWN"))),
  ae_cat("TEAE leading to death",                            quote(AESDTH == "Y"))
)

## --- n (%) with per-PERIOD denominator, then pivot periods to columns ---------
rep <- overview %>%
  left_join(denom, by = "per") %>%
  mutate(value = n_pct(nsubj, N),
         category = factor(category, levels = c(
           "Participants with any TEAE",
           "Participants with any serious TEAE",
           "Participants with any drug-related TEAE",
           "Participants with any severe TEAE",
           "TEAE leading to study-drug discontinuation",
           "TEAE leading to death"))) %>%
  arrange(category) %>%
  select(category, per, value) %>%
  pivot_wider(names_from = per, values_from = value)

ttl <- tfl_titles(num = "14.3.1.1", type = "Table",
   text = "Overview of Treatment-Emergent Adverse Events by Period",
   pop  = "Safety Population",
   foot = paste("DDI: Period 1 = victim alone (reference); Period 2 = victim + perpetrator (test).",
                "A participant is counted once per category per period. % = participants / participants dosed in that period (ADEX).",
                "TEAE = treatment-emergent. Related = AREL in Related/Possible/Probable/Definite. MedDRA v27.0."))

## rtables / gt rendering; one column per period + Total
print(rep)
