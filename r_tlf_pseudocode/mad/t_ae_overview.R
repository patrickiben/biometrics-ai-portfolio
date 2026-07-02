################################################################################
# TABLE     : t_ae_overview  (Multiple Ascending Dose)
# TITLE     : Overview of Treatment-Emergent Adverse Events by Dose Level
# POPULATION: Safety Population (SAFFL == "Y")
# INPUT     : ADAE (TRTEMFL == "Y")
# NOTE      : PSEUDOCODE. MAD = parallel ascending-dose cohorts with REPEATED
#             dosing; one treatment per participant so the column variable is the
#             dose level (dv$trtvar = TRT01A), ordered ascending by TRT01AN.
#             Each row = participants with >=1 event of a category (n_distinct
#             USUBJID), NOT event rows. n (%) per dose; % denominator = SAFFL N
#             per dose from bign(). Categories are non-mutually-exclusive (a
#             participant may appear in several rows). Read across ascending dose
#             columns for any dose-response in tolerability over the dosing
#             period.
################################################################################
source("../00_setup_helpers.R")
env <- setup(study = "CP-101", adam = "/data/adam", out = "/data/tfl")
dv  <- design_vars("MAD")                       # trtvar = TRT01A, trtnvar = TRT01AN

## --- column denominators: SAFFL N per dose level (+ Total) ------------------
## Whole-study safety overview is one treatment per participant -> ADSL denominator
## is correct here. (Per-PERIOD/per-day denominators, where needed elsewhere,
## must come from a period-bearing source such as ADEX, never ADSL.)
denom <- bign(adam$adsl, trtvar = dv$trtvar, popfl = "SAFFL")

## column (dose) order: ascending by numeric dose TRT01AN, then Total
dose_ord <- adam$adsl %>% filter(SAFFL == "Y") %>%
  distinct(trt = .data[[dv$trtvar]], trtn = .data[[dv$trtnvar]]) %>%
  arrange(trtn)

## --- treatment-emergent AE analysis set ------------------------------------
adae <- adam$adae %>% filter(SAFFL == "Y", TRTEMFL == "Y")

## "related" set, consistent & case-safe (house rule)
rel_set <- c("RELATED","POSSIBLE","PROBABLE","DEFINITE")

## --- one summary row = distinct participants meeting a category predicate -------
## Each helper counts distinct participants per dose under a dplyr filter expr.
ov_row <- function(df, where, label, ord) {
  df %>% filter(!!where) %>%
    group_by(trt = .data[[dv$trtvar]]) %>%
    summarise(nsubj = n_distinct(USUBJID), .groups = "drop") %>%
    mutate(category = label, ord = ord)
}

## --- ordered category stack ------------------------------------------------
## Severity uses AESEVN (1=Mild,2=Moderate,3=Severe); seriousness AESER;
## fatal AESDTH; discontinuation AEACN == "DRUG WITHDRAWN". For MAD the
## discontinuation / dose-interruption rows are especially informative across
## the multi-day dosing period.
## Canonical category order (matches the SAS twin): any TEAE, serious, drug-related,
## severe, drug-related serious, leading-to-discontinuation, dose-modification,
## leading-to-death. Severe test = AESEVN >= 3 in both languages.
overview <- bind_rows(
  ov_row(adae, quote(TRUE),                                       "Any TEAE",                                     1),
  ov_row(adae, quote(AESER == "Y"),                              "Any serious TEAE (SAE)",                       2),
  ov_row(adae, quote(toupper(AREL) %in% rel_set),                "Any treatment-related TEAE",                   3),
  ov_row(adae, quote(AESEVN >= 3),                               "Any severe TEAE",                              4),
  ov_row(adae, quote(AESER == "Y" & toupper(AREL) %in% rel_set), "Any treatment-related SAE",                    5),
  ov_row(adae, quote(AEACN == "DRUG WITHDRAWN"),                 "TEAE leading to study drug discontinuation",   6),
  ov_row(adae, quote(AEACN %in% c("DOSE REDUCED","DRUG INTERRUPTED")), "TEAE leading to dose reduction/interruption", 7),
  ov_row(adae, quote(AESDTH == "Y"),                             "TEAE leading to death",                        8)
)

## --- attach denominators -> n (%), with explicit 0 (0.0%) for empty cells --
doses <- dose_ord$trt                                  # ascending dose levels
grid  <- tidyr::crossing(category = unique(overview$category), trt = doses) %>%
  left_join(distinct(overview, category, ord), by = "category")

rep <- grid %>%
  left_join(overview, by = c("category","trt","ord")) %>%
  mutate(nsubj = tidyr::replace_na(nsubj, 0L)) %>%
  left_join(denom, by = "trt") %>%
  mutate(value = n_pct(nsubj, N),
         trt = factor(trt, levels = doses)) %>%        # keep ascending-dose order
  arrange(ord, trt) %>%
  select(category, ord, trt, value) %>%
  pivot_wider(names_from = trt, values_from = value) %>%
  arrange(ord) %>% select(-ord)

ttl <- tfl_titles(
  num  = "14.3.1",
  type = "Table",
  text = "Overview of Treatment-Emergent Adverse Events by Dose Level",
  pop  = "Safety Population",
  foot = paste("MAD: parallel ascending-dose cohorts, repeated dosing; columns =",
               "dose level (ascending). TEAE = treatment-emergent AE (TRTEMFL=Y).",
               "A participant is counted once per category; categories are not mutually",
               "exclusive. Related = AREL in {RELATED, POSSIBLE, PROBABLE, DEFINITE}.",
               "% = participants in category / N at dose. MedDRA v27.0."))

## --- rtables layout (MAD: split columns by dose level, ascending) -----------
# lyt <- basic_table(title = ttl$titles, main_footer = ttl$footnotes) %>%
#   split_cols_by(dv$trtvar) %>%     # column order set via factor(trt) above
#   analyze("value", afun = identity)
# tbl <- build_table(lyt, rep); tbl

print(rep)
