################################################################################
# TABLE     : t_ada_summary  (Multiple Ascending Dose)
# TITLE     : Summary of Anti-Drug Antibody (ADA) Incidence by Dose Level
# POPULATION: ADA-Evaluable Population (ADA-evaluable participants in ADIS)
# INPUT     : ADIS (immunogenicity: PARAMCD/PARAM = ADA / NAb status, baseline
#             and post-baseline; BASE/AVAL or status flags)
# NOTE      : PSEUDOCODE. Counts = distinct PARTICIPANTS (n_distinct USUBJID), NOT
#             record rows. % denominator = ADA-evaluable N per DOSE LEVEL from a
#             domain-bearing source (ADIS), NEVER one-row-per-participant ADSL.
#             MAD = parallel cohorts, REPEATED dosing, one dose level per participant
#             -> column = dv$trtvar (TRT01A = dose level; placebo pooled).
#             Repeated dosing -> a longer multi-visit on-treatment immunogenicity
#             sampling window than SAD, so the persistent/transient split and a
#             max-titer read are more informative; categories are the standard
#             set: baseline-positive, treatment-induced, treatment-boosted,
#             treatment-emergent (= induced + boosted), persistent, transient,
#             NAb-positive. Participant-level status flags come from ADIS (validated
#             ADaM derivation); we count participants, not re-derive assay results.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                      # column = TRT01A (= dose level)

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
    max_titer   = suppressWarnings(max(ADATITER, na.rm = TRUE)),        # peak titer (multi-visit)
    .groups = "drop") %>%
  mutate(max_titer = ifelse(is.finite(max_titer), max_titer, NA_real_))

## --- denominators: ADA-evaluable N per DOSE LEVEL FROM ADIS (not ADSL) ------
## ascending-dose column order keyed on the numeric dose (dv$trtnvar)
dose_order <- subj %>% distinct(trt, dosen) %>% arrange(dosen) %>% pull(trt)
denom <- subj %>% group_by(trt) %>%
  summarise(N = n_distinct(USUBJID), .groups = "drop") %>%
  bind_rows(tibble(trt = "Total", N = n_distinct(subj$USUBJID)))

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

## --- MAD add-on: max-titer summary among treatment-emergent ADA+ participants ---
## repeated dosing gives a multi-visit titer series; summarise the per-participant
## PEAK titer (Median (Min, Max)) within treatment-emergent positives per dose.
## Counts/denominator unchanged; titer is reported on positives only.
titer <- subj %>%
  filter(te_pos, !is.na(max_titer)) %>%
  group_by(trt) %>%
  summarise(n = n_distinct(USUBJID),
            med = median(max_titer), min = min(max_titer), max = max(max_titer),
            .groups = "drop") %>%
  mutate(`Max titer: Median (Min, Max)` = sprintf("%g (%g, %g)", med, min, max)) %>%
  select(trt, n, `Max titer: Median (Min, Max)`)

ttl <- tfl_titles(num = "14.5.1.1", type = "Table",
   text = "Summary of Anti-Drug Antibody (ADA) Incidence by Dose Level",
   pop  = "ADA-Evaluable Population",
   foot = paste("Each participant counted once per category (distinct USUBJID).",
                "Denominator = ADA-evaluable participants per dose level (ADIS), not ADSL.",
                "Multiple ascending dose: columns ascend by dose level (placebo pooled);",
                "longer multi-visit on-treatment ADA window than single dose.",
                "Treatment-emergent = treatment-induced + treatment-boosted.",
                "Max titer = per-participant peak across visits, treatment-emergent positives only.",
                "NAb assessed in confirmed ADA-positive samples."))

## rtables/gt rendering; treatment-emergent sub-categories indented
print(rep)
print(titer)        # MAD: peak-titer read across the multi-visit window
