################################################################################
# TABLE     : t_ae_by_relationship  (Single-/fixed-sequence DDI)
# TITLE     : Treatment-Related Adverse Events by System Organ Class and
#             Preferred Term, by Period
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y"); ADEX for per-PERIOD dosed denominators
# NOTE      : PSEUDOCODE. Restricted to RELATED TEAEs. "Related" set is consistent
#             and case-safe: toupper(AREL) %in% c("RELATED","POSSIBLE","PROBABLE",
#             "DEFINITE"). Columns = dv$byperiod (APERIODC): Period 1 reference
#             (victim alone), Period 2 test (victim + perpetrator). Counts =
#             distinct PARTICIPANTS, NOT event rows. % denominator = participants DOSED
#             per APERIOD (ADEX, SAFFL) -- NOT ADSL.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # TRTA + APERIOD/APERIODC

period_col <- dv$byperiod[2]                    # "APERIODC"
rel_set    <- c("RELATED","POSSIBLE","PROBABLE","DEFINITE")

## --- per-PERIOD denominator (period-bearing source: ADEX) ---------------------
denom <- adam$adex %>%
  filter(SAFFL == "Y") %>%
  group_by(per = .data[[period_col]]) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop")

## --- RELATED treatment-emergent AEs (case-safe relationship set) --------------
adae <- adam$adae %>%
  filter(SAFFL == "Y", TRTEMFL == "Y", toupper(AREL) %in% rel_set)

ae_by <- function(byvars) {
  adae %>%
    group_by(per = .data[[period_col]], across(all_of(byvars))) %>%
    summarise(nsubj = n_distinct(USUBJID), .groups = "drop")
}

any_rel <- adae %>% group_by(per = .data[[period_col]]) %>%
  summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
  mutate(AESOC = NA_character_, AEDECOD = NA_character_, level = 0L,
         term = "Participants with any related TEAE")

soc   <- ae_by("AESOC")               %>% mutate(level = 1L, term = AESOC)
socpt <- ae_by(c("AESOC","AEDECOD"))  %>% mutate(level = 2L, term = paste0("   ", AEDECOD))

soc_ord <- soc   %>% group_by(AESOC)          %>% summarise(socn = sum(nsubj), .groups = "drop")
pt_ord  <- socpt %>% group_by(AESOC, AEDECOD) %>% summarise(ptn  = sum(nsubj), .groups = "drop")

rep <- bind_rows(any_rel, soc, socpt) %>%
  left_join(denom, by = "per") %>%
  mutate(value = n_pct(nsubj, N)) %>%
  left_join(soc_ord, by = "AESOC") %>%
  left_join(pt_ord,  by = c("AESOC","AEDECOD")) %>%
  arrange(desc(socn), AESOC, level, desc(ptn)) %>%
  select(term, level, per, value) %>%
  pivot_wider(names_from = per, values_from = value)

ttl <- tfl_titles(num = "14.3.1.4", type = "Table",
   text = "Treatment-Related Adverse Events by System Organ Class and Preferred Term, by Period",
   pop  = "Safety Population",
   foot = paste("DDI: Period 1 = victim alone (reference); Period 2 = victim + perpetrator (test).",
                "Related = AREL in Related/Possible/Probable/Definite (case-insensitive). Participant counted once at each level within a period.",
                "% = participants / participants dosed in that period (ADEX). MedDRA v27.0."))

## rtables / gt rendering; SOC bold (level 1), PT indented (level 2)
print(rep)
