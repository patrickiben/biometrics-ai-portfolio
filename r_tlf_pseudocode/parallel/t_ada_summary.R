################################################################################
# TABLE     : t_ada_summary  (Parallel-group)
# TITLE     : Summary of Anti-Drug Antibody (ADA) Incidence by Treatment
# POPULATION: ADA-Evaluable Population (ADA-evaluable participants in ADIS)
# INPUT     : ADIS (immunogenicity: PARAMCD/PARAM = ADA / NAb status, baseline
#             and post-baseline; BASE/AVAL or status flags)
# NOTE      : PSEUDOCODE. Counts = distinct PARTICIPANTS (n_distinct USUBJID), NOT
#             record rows. % denominator = ADA-evaluable N per treatment from a
#             period-/domain-bearing source (ADIS), NEVER one-row-per-participant
#             ADSL. Parallel-group: one treatment per participant -> column =
#             dv$trtvar (TRT01A, = dose for ascending-dose layouts).
#             Standard immunogenicity categories: baseline-positive,
#             treatment-induced, treatment-boosted, treatment-emergent (= induced
#             + boosted), persistent, transient, NAb-positive.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("PARALLEL")                 # column = TRT01A (= dose)

## one row per participant's immunogenicity status, derived from ADIS records.
## ADIS carries the validated ADaM-derived status flags; we count participants, not
## re-derive assay results.
adis <- adam$adis %>% filter(ADAFL == "Y")     # ADA-evaluable records

## --- collapse to participant-level immunogenicity status (flags from ADIS) ------
subj <- adis %>%
  group_by(USUBJID, trt = .data[[dv$trtvar]]) %>%
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

## --- denominators: ADA-evaluable N per treatment from the ADSL ADAFL flag ----
## Canonical ADA-evaluable population = ADSL ADAFL=='Y' (one flag in both
## languages), matching the SAS twin's %bign(... popfl=ADAFL). ADSL.ADAFL is the
## participant-level ADA-evaluable flag per the ADIS spec.
denom <- bign(adam$adsl, trtvar = dv$trtvar, popfl = "ADAFL")

## --- category counts = distinct participants per treatment ---------------------
cat_row <- function(flagvar, label, ord) {
  subj %>% filter(.data[[flagvar]]) %>%
    group_by(trt) %>% summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
    mutate(category = label, ord = ord)
}
n_eval <- subj %>% group_by(trt) %>%
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

## --- n (%) with ADIS-derived denominator -----------------------------------
rep <- rows %>%
  left_join(denom, by = "trt") %>%
  mutate(value = n_pct(nsubj, N)) %>%
  select(category, ord, trt, value) %>%
  pivot_wider(names_from = trt, values_from = value) %>%
  arrange(ord)

ttl <- tfl_titles(num = "14.5.1.1", type = "Table",
   text = "Summary of Anti-Drug Antibody (ADA) Incidence by Treatment",
   pop  = "ADA-Evaluable Population",
   foot = paste("Each participant counted once per category (distinct USUBJID).",
                "Denominator = ADA-evaluable participants per treatment (ADSL ADAFL='Y').",
                "Treatment-emergent = treatment-induced + treatment-boosted.",
                "NAb assessed in confirmed ADA-positive samples."))

## rtables/gt rendering; treatment-emergent sub-categories indented
print(rep)
