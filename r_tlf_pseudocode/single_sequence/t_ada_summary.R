################################################################################
# TABLE     : t_ada_summary  (Single-/Fixed-Sequence DDI)
# TITLE     : Summary of Anti-Drug Antibody (ADA) Incidence by Period
# POPULATION: ADA-Evaluable Population (ADA-evaluable participants in ADIS)
# INPUT     : ADIS (immunogenicity: PARAMCD/PARAM = ADA / NAb status, baseline
#             and post-baseline; BASE/AVAL or status flags; APERIOD/APERIODC)
# NOTE      : PSEUDOCODE. Counts = distinct PARTICIPANTS (n_distinct USUBJID), NOT
#             record rows. PERIOD table -> columns = dv$byperiod (APERIODC):
#             Period 1 = reference (victim alone), Period 2 = test (victim +
#             perpetrator). NO randomized sequence. % denominator = ADA-evaluable
#             N PER PERIOD from a period-bearing source (ADIS), NEVER one-row-
#             per-participant ADSL. Standard immunogenicity categories: baseline-
#             positive, treatment-induced, treatment-boosted, treatment-emergent
#             (= induced + boosted), persistent, transient, NAb-positive.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SINGLESEQ")                 # byperiod = c("APERIOD","APERIODC")
options(tfl.study = env$study)
perC <- dv$byperiod[2]                          # character period label

## ADIS carries the validated ADaM-derived status flags; we count participants per
## period, not re-derive assay results. A participant can be ADA-evaluable in both
## periods -> status collapsed to participant x period.
adis <- adam$adis %>% filter(ADAFL == "Y")     # ADA-evaluable records

## --- collapse to participant x PERIOD immunogenicity status (flags from ADIS) ---
subj <- adis %>%
  group_by(USUBJID, per = .data[[perC]]) %>%
  summarise(
    evaluable   = TRUE,
    base_pos    = any(toupper(BASEADA)  == "POSITIVE", na.rm = TRUE),   # baseline ADA+
    te_pos      = any(toupper(TEADAFL)  == "Y",        na.rm = TRUE),   # treatment-emergent ADA+
    induced     = any(toupper(ADAINDFL) == "Y",        na.rm = TRUE),   # treatment-induced
    boosted     = any(toupper(ADABSTFL) == "Y",        na.rm = TRUE),   # treatment-boosted
    persistent  = any(toupper(ADAPERFL) == "Y",        na.rm = TRUE),   # persistent
    transient   = any(toupper(ADATRNFL) == "Y",        na.rm = TRUE),   # transient
    nab_pos     = any(toupper(NABFL)    == "Y",        na.rm = TRUE),   # NAb+
    .groups = "drop")

## --- denominators: ADA-evaluable N PER PERIOD from ADIS (not ADSL) ----------
denom <- subj %>% group_by(per) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop")

## --- category counts = distinct participants per period ------------------------
cat_row <- function(flagvar, label, ord) {
  subj %>% filter(.data[[flagvar]]) %>%
    group_by(per) %>% summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
    mutate(category = label, ord = ord)
}
n_eval <- subj %>% group_by(per) %>%
  summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
  mutate(category = "ADA-evaluable participants", ord = 0L)

rows <- bind_rows(
  n_eval,
  cat_row("base_pos",   "Baseline ADA-positive",                  1L),
  cat_row("te_pos",     "Treatment-emergent ADA-positive",        2L),
  cat_row("induced",    "  Treatment-induced",                    3L),
  cat_row("boosted",    "  Treatment-boosted",                    4L),
  cat_row("persistent", "  Persistent",                           5L),
  cat_row("transient",  "  Transient",                            6L),
  cat_row("nab_pos",    "Neutralizing antibody (NAb)-positive",   7L))

## --- n (%) with ADIS-derived PER-PERIOD denominator ------------------------
rep <- rows %>%
  left_join(denom, by = "per") %>%
  mutate(value = n_pct(nsubj, N)) %>%
  select(category, ord, per, value) %>%
  pivot_wider(names_from = per, values_from = value) %>%
  arrange(ord)

ttl <- tfl_titles(num = "14.5.1.1", type = "Table",
   text = "Summary of Anti-Drug Antibody (ADA) Incidence by Period",
   pop  = "ADA-Evaluable Population",
   foot = paste("Single-fixed-sequence DDI: Period 1 = reference (victim alone),",
                "Period 2 = test (victim + perpetrator). Each participant counted once",
                "per category per period (distinct USUBJID). Denominator =",
                "ADA-evaluable participants per period (ADIS), not ADSL.",
                "Treatment-emergent = treatment-induced + treatment-boosted.",
                "NAb assessed in confirmed ADA-positive samples."))

## rtables/gt rendering; treatment-emergent sub-categories indented
print(rep)
