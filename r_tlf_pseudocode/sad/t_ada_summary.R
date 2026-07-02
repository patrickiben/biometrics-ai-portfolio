################################################################################
# TABLE     : t_ada_summary  (Single Ascending Dose)
# TITLE     : Summary of Anti-Drug Antibody (ADA) Incidence by Dose Level
# POPULATION: ADA-Evaluable Population (ADA-evaluable participants in ADIS)
# INPUT     : ADIS (immunogenicity: PARAMCD/PARAM = ADA / NAb status, baseline
#             and post-baseline; BASE/AVAL or status flags)
# NOTE      : PSEUDOCODE. Counts = distinct PARTICIPANTS (n_distinct USUBJID), NOT
#             record rows. % denominator = ADA-evaluable population N per DOSE
#             LEVEL from the ADSL ADAFL flag (bign), the SAME source as the SAS
#             twin -- so both deliverables share one ADA-evaluable denominator.
#             SAD = parallel cohorts, one dose per participant -> column = dv$trtvar
#             (TRT01A = dose level; placebo pooled). Single dose -> a short
#             single-dose follow-up window for immunogenicity; categories are
#             still the standard set: baseline-positive, treatment-induced,
#             treatment-boosted, treatment-emergent (= induced + boosted),
#             persistent, transient, NAb-positive.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("SAD")                      # column = TRT01A (= dose level)

## one row per participant's immunogenicity status, derived from ADIS records.
## ADIS carries the validated ADaM-derived status flags; we count participants, not
## re-derive assay results.
adis <- adam$adis %>% filter(ADAFL == "Y")     # ADA-evaluable records

## --- collapse to participant-level immunogenicity status (flags from ADIS) ------
subj <- adis %>%
  group_by(USUBJID, trt = .data[[dv$trtvar]], dosen = .data[[dv$trtnvar]]) %>%
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

## --- denominators: ADA-evaluable population N per DOSE LEVEL from ADSL ADAFL --
## SAME source as the SAS twin (%bign popfl=ADAFL); column order keyed on dose.
dose_order <- subj %>% distinct(trt, dosen) %>% arrange(dosen) %>% pull(trt)
denom <- bign(adam$adsl, trtvar = dv$trtvar, popfl = "ADAFL")  # ADA-evaluable N per dose

## --- category counts = distinct participants per dose level --------------------
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

## --- n (%) with ADIS-derived denominator; columns ascend by dose -----------
rep <- rows %>%
  left_join(denom, by = "trt") %>%
  mutate(value = n_pct(nsubj, N)) %>%
  select(category, ord, trt, value) %>%
  pivot_wider(names_from = trt, values_from = value) %>%
  select(category, ord, any_of(dose_order), any_of("Total")) %>%
  arrange(ord)

ttl <- tfl_titles(num = "14.5.1.1", type = "Table",
   text = "Summary of Anti-Drug Antibody (ADA) Incidence by Dose Level",
   pop  = "ADA-Evaluable Population",
   foot = paste("Each participant counted once per category (distinct USUBJID).",
                "Denominator = ADA-evaluable participants per dose level (ADIS), not ADSL.",
                "Single ascending dose: columns ascend by dose level (placebo pooled).",
                "Treatment-emergent = treatment-induced + treatment-boosted.",
                "NAb assessed in confirmed ADA-positive samples."))

## rtables/gt rendering; treatment-emergent sub-categories indented
print(rep)
